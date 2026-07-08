---
title: 08 - F2F Gap-Closing Checklist (Networking + Coding)
description: "Final pre-F2F checklist for the two flagged gaps not covered by earlier prep: foundational networking theory (OSI, TCP/UDP, DNS, L4/L7, NAT - train-reading friendly) and a timed coding warm-up to reverse the post-Codility decay."
tags: [interview-prep, nab, networking, coding-practice, checklist, layer-14]
status: draft
difficulty: intermediate
layer: 14
domain: interview-prep
created: 2026-07-08
---

# F2F Gap-Closing Checklist (Networking + Coding)

> Two flagged gaps from the JD's "Mandatory Skills" review, not covered by the earlier prep notes ([[master-study-checklist|Master Study Checklist]], the question banks). Pre-F2F prep for July 11, 2026; compiled July 8 from the prep sync.

---

## 1. Networking Fundamentals (train reading window — offline-safe)

JD requirement: "deep understanding of infrastructure and networking" — platform-specific pieces (K8s Services/DNS, AWS VPC) are already covered; this checklist is the **foundational theory layer** underneath that. Primary reading: [[networking-fundamentals|Networking Fundamentals (OSI, TCP/UDP, NAT)]].

- [ ] **OSI Model** — 7 layers, what lives at each, and one real troubleshooting example per layer (esp. L3 vs L4 vs L7) — [[networking-fundamentals|Networking Fundamentals (OSI, TCP/UDP, NAT)]]
- [ ] **TCP vs UDP** — handshake (SYN/SYN-ACK/ACK), reliability/ordering guarantees, when each is used (e.g., why gRPC/HTTP2 use TCP, why DNS/QUIC lean UDP) — [[networking-fundamentals|Networking Fundamentals (OSI, TCP/UDP, NAT)]]
- [ ] **DNS resolution flow** — recursive vs authoritative resolver, record types (A/AAAA/CNAME/MX/TXT), TTL/caching behavior, what changes in a K8s cluster (CoreDNS, service discovery) — [[dns|DNS]] (incl. the CoreDNS interview-prep section)
- [ ] **L4 vs L7 load balancing** — what each inspects (IP/port vs HTTP headers/path), why L7 enables things like path-based routing or canary splits, where this maps to K8s Ingress vs Service (ClusterIP/NodePort/LoadBalancer) — [[load-balancing|Load Balancing]], [[kubernetes-services|Kubernetes Services]]
- [ ] **NAT** — source NAT vs destination NAT, why it matters for private subnets talking to the internet (AWS NAT Gateway), and how it relates to Pod-to-Pod vs Pod-to-external traffic in K8s networking — [[networking-fundamentals|Networking Fundamentals (OSI, TCP/UDP, NAT)]], [[aws-platform-questions|AWS Platform Engineering Question Bank]]
- [ ] **Tie-back exercise** (do this last, 10 min): for each concept above, write one sentence connecting it to something in your actual Airflow/integration architecture (e.g., "our SFTP-to-Jira sync relies on DNS TTL behavior when X service resolves Y")

## 2. Coding Warm-Up (Thu/Fri hotel, browser-based)

Flagged as untouched since the Codility OA pass (2/3 solved) — highest-leverage gap since it's been over a week with zero reinforcement. Pattern refreshers: [[lp-dsa|Learning Path - DSA]].

- [ ] **Pick 2-3 problems matching your Codility pattern** — if the OA leaned array/string manipulation or sliding-window, stay in that lane rather than branching into trees/graphs cold
- [ ] **Problem 1 — timed, no hints** (simulate OA conditions, ~30-45 min)
- [ ] **Problem 2 — timed, then review** (solve, then explicitly check time/space complexity out loud as if explaining to an interviewer) — [[big-o-notation|Big O Notation]]
- [ ] **Problem 3 (optional, only if 1-2 go smoothly)** — pick something slightly harder or from the domain you missed on the actual OA
- [ ] **Explain-out-loud pass** — for each solved problem, do a 2-minute verbal walkthrough of your approach as you would in the F2F project-discussion round (NAB's format weights this heavily over narrow tool trivia — [[real-interview-intelligence|Real Interview Intelligence]])

## Still Open (not part of this checklist, tracked separately)

- [ ] Hotel location → needed to calculate commute time to NAB Innovation Centre India (Cherry Hills, Domlur)

---

## Related Notes

- [[networking-fundamentals|Networking Fundamentals (OSI, TCP/UDP, NAT)]]
- [[master-study-checklist|Master Study Checklist]]
- [[prep-plan|Prioritized Prep Plan]]
- [[real-interview-intelligence|Real Interview Intelligence]]
- [[lp-interview-prep|Learning Path - Interview Prep]]
