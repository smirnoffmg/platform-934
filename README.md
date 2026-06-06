# platform-934

Self-hosted, single-user censorship-resistant proxy for Russia and China.

**Primary stack:** VLESS + XTLS-Vision + REALITY on a random high port, deployed on a clean-IP VPS. AmneziaWG (UDP) as the Russia fallback - bypasses TSPU's 16 KB TCP curtain. Hysteria2 as throughput fallback on lossy paths.

**Operations:** one command to deploy, one to rotate.

```
make deploy   # provision a fresh VPS end-to-end
make rotate   # new port + SNI + keys, verified in <5 min
```

Ansible + SOPS-encrypted secrets, strictly no plaintext credentials in the repo.
