---
title: 08 - Networking Fundamentals (OSI, TCP/UDP, NAT)
description: "The foundational theory under every platform-networking conversation: the OSI model as a troubleshooting vocabulary, TCP's handshake and guarantees vs UDP's speed, and how NAT lets private networks reach the internet - with the mapping to Kubernetes and AWS at each step."
tags: [networking, osi, tcp, udp, nat, layer-7, system-design]
status: draft
difficulty: intermediate
layer: 7
domain: system-design
created: 2026-07-08
---

# Networking Fundamentals (OSI, TCP/UDP, NAT)

> Platform interviews rarely ask "recite the OSI model" - they ask "the service is unreachable, walk me through it," and the OSI layers are the checklist you're implicitly walking. This note is the theory floor under [[dns|DNS]], [[load-balancing|Load Balancing]], Kubernetes networking, and VPC design.

---

## Quick Reference

**Core idea:**
- **OSI layers, with a real troubleshooting example each:**
  - L1 Physical / L2 Data Link (frames, MAC) - cloud abstracts these away; "NIC down" territory
  - **L3 Network** (IP, routing) - *packet can't reach the host*: wrong route table, no NAT gateway, subnet misconfiguration
  - **L4 Transport** (TCP/UDP, ports) - *host reachable, port isn't*: security group blocks 5432, connection refused, SYN timeout
  - L5/L6 Session/Presentation - in practice: TLS handshake failures, cert expiry live around here
  - **L7 Application** (HTTP, gRPC, DNS-as-protocol) - *connection fine, request wrong*: 403s, wrong Host header, path routing
- **TCP**: connection-oriented - three-way handshake (SYN → SYN-ACK → ACK), ordered delivery, retransmission, flow/congestion control; the default for anything that can't lose bytes (HTTP/1.1, HTTP/2, gRPC, databases)
- **UDP**: connectionless datagrams - no handshake, no ordering, no retransmission; latency wins for DNS queries, metrics/logs fire-and-forget, video; QUIC (HTTP/3) builds TCP-like reliability *on top of* UDP to beat TCP's handshake latency
- **NAT**: rewriting IPs/ports at a boundary - **SNAT** (source): many private IPs share one public IP outbound (AWS NAT Gateway, home routers); **DNAT** (destination): one public IP forwards inbound to a private target (load balancers do this conceptually)
- Security groups think in L3/L4 terms (IP + port + protocol); Ingress and service meshes think in L7 terms (host, path, header)

**Tricky points:**
- "Connection refused" (RST - port closed/no listener) vs "connection timed out" (SYN dropped - firewall/security group/route) - the single most useful L4 diagnostic distinction
- TCP's handshake costs a round trip *before* any data - why connection pooling and keep-alive matter, and why QUIC exists
- NAT breaks the "my source IP identifies me" assumption - downstream services see the NAT gateway's IP, not the pod's or laptop's
- Kubernetes pod-to-pod traffic is *not* NATed (flat network - a CNI requirement); pod-to-*external* traffic is SNATed at the node, then again at the AWS NAT Gateway if in a private subnet

---

## What It Is

The OSI model earns its place as a *debugging protocol*, not trivia. "Users can't reach the service" decomposes bottom-up: can packets route to the host at all (L3 - route tables, NAT, peering)? Does the specific port accept connections (L4 - security groups, listeners, the refused-vs-timeout distinction)? Does the application answer correctly (L7 - TLS, headers, routing rules, auth)? Saying "this smells like L4 - let me check security groups before we blame the app" is exactly the signal a platform interviewer is listening for. The layers also name the load-balancer split: an NLB balances L4 (IP/port, no payload inspection); an ALB or Ingress controller balances L7 (host/path/header - which is what makes path-based routing and canary traffic splits possible) - the full comparison lives in [[load-balancing|Load Balancing]].

TCP vs UDP is a contract difference. TCP buys you a connection: the three-way handshake (SYN, SYN-ACK, ACK) establishes sequence numbers, after which the stack guarantees ordering, retransmits losses, and paces senders via flow and congestion control. Everything that cannot tolerate silent loss - HTTP, gRPC (which needs HTTP/2's single ordered stream), database wire protocols - rides TCP. UDP is stamped-and-mailed datagrams: no setup round trip, no state, no guarantees. DNS queries fit perfectly (one tiny question, one tiny answer - a lost query is just re-asked); so do high-volume telemetry and media, where a retransmitted stale packet is worth less than the next fresh one. The modern wrinkle worth citing: QUIC/HTTP-3 rebuilds reliability in userspace *over UDP*, precisely to escape TCP's handshake latency and head-of-line blocking - proof the choice is engineering trade-off, not dogma.

NAT is address rewriting at a network boundary, and it is load-bearing in both cloud and cluster networking. Source NAT solves "private things need to reach the internet": instances in a private subnet have no public IPs, so their outbound packets are rewritten to the NAT Gateway's public IP (with per-connection port mapping to demultiplex returns). That's the AWS pattern - private subnets route `0.0.0.0/0` to a NAT Gateway in a public subnet ([[aws-platform-questions|AWS Platform Engineering Question Bank]]). Destination NAT is the inbound mirror: rewrite a public destination to a private target. In Kubernetes, the rule to remember: pod-to-pod traffic is un-NATed by design - every pod sees real pod IPs on a flat network (the CNI's job) - but pod-to-external traffic is SNATed at the node boundary, so external services see node (or NAT Gateway) IPs. That asymmetry explains real behaviors: why allow-listing "the cluster" externally means allow-listing NAT/node IPs, and why in-cluster services can see true client pod IPs while external ones cannot.

---

## How It Actually Works

The L3/L4/L7 walk, as a triage script:

```bash
# L3 - can I reach the host at all?
ping 10.0.2.15                      # ICMP (often blocked; absence isn't proof)
traceroute 10.0.2.15                # where does routing stop?

# L4 - is the port open?
nc -zv 10.0.2.15 5432               # "refused" = reachable, nothing listening
                                    # "timed out" = SYN dropped: SG/NACL/route
# L7 - is the application right?
curl -v https://api.internal/health # TLS handshake, status code, headers
dig api.internal                    # and is DNS even pointing where you think?
```

TCP handshake and teardown, compressed: client sends SYN (with initial sequence number) → server replies SYN-ACK → client ACKs → data flows as ordered, acknowledged segments → FIN/ACK pairs close each direction. The handshake's round trip is why TLS-over-TCP costs 2-3 RTTs before the first byte of HTTP - and why keep-alive connections and connection pools are performance features, not conveniences.

SNAT in one picture: pod `10.0.5.7` in a private subnet calls `api.github.com` → node rewrites source to node IP `10.0.2.15` (kube SNAT) → NAT Gateway rewrites to public `52.x.x.x`, recording `(52.x.x.x:61042 ↔ 10.0.2.15:33210)` in its translation table → GitHub replies to `52.x.x.x:61042` → mappings unwind in reverse.

---

## How It Connects

DNS is the L7 protocol most worth knowing end-to-end - resolution chain, record types, TTL - with CoreDNS as the in-cluster twist.

[[dns|DNS]]

L4 vs L7 load balancing maps directly onto K8s Service (ClusterIP/NodePort/LoadBalancer) vs Ingress.

[[load-balancing|Load Balancing]], [[kubernetes-services|Kubernetes Services]]

The VPC design questions - subnets, route tables, NAT Gateway, security groups vs NACLs - are this note applied to AWS.

[[aws-platform-questions|AWS Platform Engineering Question Bank]], [[ec2-security-groups|EC2 Security Groups]]

HTTP's request/response mechanics sit one layer up.

[[http-basics|HTTP Basics]]

---

## Common Misconceptions

Misconception 1: "UDP is unreliable, so serious systems avoid it."
Reality: UDP is *unguaranteed*, which is different from unusable. DNS runs the internet on it; QUIC carries a growing share of web traffic over it. When the application layer can tolerate or manage loss, skipping TCP's handshake and head-of-line blocking is a feature.

Misconception 2: "Connection refused and connection timeout are the same failure."
Reality: Refused means the packet *arrived* and the host answered "nothing listening" (RST) - the network path is fine, look at the process/port. Timeout means the SYN vanished - look at security groups, NACLs, and routing. Conflating them sends you debugging the wrong layer.

Misconception 3: "Kubernetes NATs everything anyway."
Reality: The Kubernetes network model *requires* pod-to-pod traffic be un-NATed - real pod IPs end to end. NAT enters only at boundaries: leaving the node for external destinations, or entering through Services' virtual IPs (kube-proxy DNAT). Knowing where NAT does and doesn't happen is what makes CNI and traffic debugging tractable.

---

## Interview Angle

Common question forms:
- "A service in a private subnet can't reach an external API - debug it."
- "TCP vs UDP - and why does gRPC need TCP while DNS uses UDP?"
- "What's the difference between an NLB and an ALB?" (L4 vs L7 in disguise)

Answer frame:
Structure any unreachability question as the L3 → L4 → L7 walk, naming the tool and the cloud object at each layer (route table/NAT at L3, security group + refused-vs-timeout at L4, TLS/headers/DNS at L7). TCP vs UDP: state the contract (handshake, ordering, retransmission) then argue from the application's loss tolerance; cite QUIC to show currency. NAT: SNAT for private-out (NAT Gateway), DNAT for public-in, plus the K8s rule - pods talk un-NATed inside, SNAT at the boundary out.

---

## Related Notes

- [[dns|DNS]]
- [[load-balancing|Load Balancing]]
- [[kubernetes-services|Kubernetes Services]]
- [[aws-platform-questions|AWS Platform Engineering Question Bank]]
- [[http-basics|HTTP Basics]]
