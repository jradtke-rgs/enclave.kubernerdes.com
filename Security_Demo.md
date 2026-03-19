# RGS Security (NeuVector) Demo Walkthrough: Monitor → Protect Mode

## Overview

This walkthrough guides you through a live demonstration of SUSE Security (NeuVector) using a running container in the `aperture-sci` namespace. You'll observe network behavior in Monitor mode, then flip to Protect mode and witness real-time enforcement blocking unauthorized connections.

---

## The Setup

Before you begin, confirm the test container is running and active. The `chell-test` container in the `aperture-sci` namespace is continuously making outbound HTTPS requests every 5 seconds:

See [Scripts/80_deploy_random_apps.sh](Scripts/80_deploy_random_apps.sh) for deploying the simple container for this demo.

```bash
kubectl get pods -n aperture-sci
```

You should see `chell-test` in a `Running` state. Internally, it's executing this loop:

```bash
curl -svo /dev/null https://www.fastly.com 2>&1 | grep subjectAltName
```

This curl call validates the TLS certificate on `www.fastly.com` and prints the Subject Alternative Name — confirming both DNS resolution and TLS negotiation are succeeding. This is your **known-good baseline traffic**.

---

## Part 1: Observing Traffic in Monitor Mode

### Step 1 — Log into the NeuVector Console

Navigate to your NeuVector management UI. From the left sidebar, go to:

**Network Activity** → you should see a live network graph populating with your cluster's workloads.

> 💡 **Tip for the audience:** NeuVector is watching every network connection at Layer 7 — not just IP/port, but protocol and payload. Everything happening right now is being recorded.

### Step 2 — Locate the `chell-test` Container

In the Network Activity view, find the `aperture-sci` namespace grouping. Click on the `chell-test` service/pod. You should see:

- An **outbound HTTPS connection** being established every ~5 seconds to `www.fastly.com`
- NeuVector recording the destination, protocol (HTTPS/443), and connection frequency

This traffic appears in **green** or as an allowed/observed connection — because NeuVector is currently in **Monitor mode**, which means it's *learning* and *alerting*, but **not blocking** anything.

### Step 3 — Review the Learned Network Rules

Navigate to **Policy** → **Network Rules** and filter to the `aperture-sci` namespace.

You should see NeuVector has auto-discovered and documented:

- **Source:** `chell-test` (aperture-sci namespace)
- **Destination:** `www.fastly.com` (external)
- **Protocol:** HTTPS / TCP 443

> 🎯 **Key talking point:** This is NeuVector's *behavioral baseline*. In Monitor mode, it's building a model of "what normal looks like" for this workload. Every connection gets catalogued. When you switch to Protect mode, anything that deviates from this baseline becomes a candidate for enforcement.

### Step 4 — Observe the Live Security Events

Go to **Notifications** → **Security Events**. You may see informational events being logged for the outbound connections. Notice that in Monitor mode, these are recorded but the traffic flows freely.

> 🎯 **Key talking point:** Your security team gets visibility without disrupting the application. This is how you build confidence before enforcing — you watch first, then act.

---

## Part 2: Switching to Protect Mode

### Step 5 — Change the Group Policy to Protect Mode

Navigate to **Policy** → **Groups**. Find the group corresponding to `chell-test` in the `aperture-sci` namespace (it may appear as `nv.chell-test.aperture-sci` or similar).

Click on the group, then look for the **Policy Mode** setting. You'll see three options:

| Mode | Behavior |
|------|----------|
| **Discover** | Learning only — no alerts, no blocks |
| **Monitor** | Alert on violations — no blocks |
| **Protect** | Enforce — violations are **blocked** |

Select **Protect** and confirm. The change takes effect immediately — NeuVector's enforcement engine now has an active ruleset for this workload.

> 🎯 **Key talking point:** This is a per-group, per-workload control. You can have some services in Discover, others in Monitor, and production-critical workloads in Protect — all simultaneously. Granularity is the point.

### Step 6 — Verify the Legitimate Traffic Still Flows

Give it 10–15 seconds. The `chell-test` container's existing curl loop to `www.fastly.com` should **continue to work** because NeuVector learned that connection during the Monitor phase and it is now part of the allowlist.

You can verify by watching the logs:

```bash
kubectl logs -f chell-test -n aperture-sci
```

You should continue to see output like:

```
*  subjectAltName: host "www.fastly.com" matched cert's "*.fastly.com"
```

> 🎯 **Key talking point:** Legitimate, learned traffic is unaffected. NeuVector enforces *zero-trust* — not *zero-connectivity*. The model is "deny everything not explicitly allowed," but the allowlist was built automatically from observed behavior.

---

## Part 3: Demonstrating Enforcement (Protect Mode in Action)

### Step 7 — Exec into the Container

Now you'll attempt connections that were never part of the learned baseline.

```bash
kubectl exec -it chell-test -n aperture-sci -- /bin/sh
```

You should get a shell prompt inside the container.

### Step 8 — Attempt an Unauthorized Connection (curl to google.com)

From inside the container, run:

```bash
curl google.com
```

**Expected result:** The connection is **blocked**. You'll see either a connection timeout, connection refused, or an immediate failure — NeuVector's enforcement engine drops the packet before it leaves the container's network namespace.

```
curl: (6) Could not resolve host: google.com
# or
curl: (7) Failed to connect to google.com port 80
```

> 🎯 **Key talking point:** `google.com` was never part of this container's learned behavior. NeuVector has no rule permitting it, so in Protect mode it doesn't get through — full stop. This is east-west and north-south enforcement at the container level, not at the perimeter.

Back in the NeuVector console, navigate to **Notifications** → **Security Events**. You should see a **violation event** with:

- Source: `chell-test`
- Destination: `google.com`
- Action: **Denied / Blocked**
- Timestamp matching your attempt

### Step 9 — Attempt a Second Unauthorized Connection (wget to fastly.com)

Still inside the container, run:

```bash
wget https://www.fastly.com 2>&1 | grep subjectAltName
```

**Expected result:** This connection is also **blocked**, even though the *destination* (`www.fastly.com`) was in the learned baseline.

> 🎯 **Key talking point:** This is the subtle but critical part. `wget` is a *different process* with a *different network behavior signature* than `curl`. NeuVector enforces at the process level — not just destination IP. The allowed rule was built for `curl` making HTTPS connections on a 5-second cycle. `wget` in an interactive shell session doesn't match that profile, so it's denied.

> This is how you catch lateral movement and container compromise — an attacker who gains shell access can't just `wget` an exfiltration endpoint or phone home, even if that endpoint was legitimately used by the application itself.

You should see a second violation event in the NeuVector console for this attempt as well.

---

## Part 4: Closing the Loop

### Step 10 — Review the Violation Timeline

In **Notifications** → **Security Events**, review the two violation events side by side. Point out:

- **What was attempted** (process, destination, protocol)
- **What action NeuVector took** (blocked)
- **How this maps to a real threat scenario** — unauthorized outbound connections, potential C2 callout, data exfiltration attempt

### Step 11 — Optional: Show the Network Graph Differential

Return to **Network Activity**. The attempted (blocked) connections may appear as **red dotted lines** in the network graph — visually distinct from the green allowed connection to Fastly. This gives a clear "what was allowed vs. what was blocked" picture for a non-technical audience.

---

## Demo Summary

| Action | Mode | Result |
|--------|------|--------|
| `curl fastly.com` (automated loop) | Monitor | ✅ Allowed — observed and logged |
| Switch to Protect | — | Enforcement enabled, learned rules become policy |
| `curl fastly.com` (automated loop) | Protect | ✅ Allowed — matches learned baseline |
| `curl google.com` (interactive) | Protect | 🚫 Blocked — no learned rule exists |
| `wget fastly.com` (interactive) | Protect | 🚫 Blocked — process signature mismatch |

---

## Key Takeaways for Your Audience

**Behavioral baseline, not signature-based.** NeuVector doesn't use CVE signatures to block things. It models what "normal" looks like for each workload and enforces that model. Zero-day exploits that use legitimate-looking processes still get caught.

**Process-level enforcement.** The unit of enforcement isn't IP or port — it's the container process making the connection. This is enforcement inside the pod, before traffic ever hits the network.

**Graduated rollout.** Discover → Monitor → Protect gives operators the ability to build confidence before enforcing. You don't have to choose between blind blocking and total permissiveness.

**Full audit trail.** Every allowed and blocked connection is logged with enough context to reconstruct what happened, when, and from where — directly satisfying audit and compliance requirements for IL4/IL5 environments.
