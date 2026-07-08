# Self-hosting Xentral for an AI connector, and why it is a dead end

A written record of a real experiment, so the next person who wants to self-host
Xentral to point an AI agent or MCP at it can read this in five minutes instead
of spending a day proving what the market already decided.

Short version. You cannot self-host modern Xentral. The only self-hostable option
is OpenXE, the community fork of the old code, and it speaks a different API
generation. If your goal was a self-hosted Xentral for a modern integration, that
goal does not exist. Stop here and save the time.

This repo carries the full reasoning, the deploy recipe that does work if you
still want OpenXE, the exact traps that cost hours, and the honest verdict.

No secrets, tokens, IP addresses, or passwords appear anywhere in this repo, on
purpose.

## Why this exists

While building an MCP connector for the modern Xentral cloud API, the obvious
question came up. Can I run my own Xentral to develop against, instead of paying
for a cloud tenant. The answer turned out to be no, for reasons that are
structural and permanent. Rather than let that lesson evaporate, it is written
down here so others can skip the experiment.

## 1. A short history of how Xentral got here

Xentral started in the early 2010s. Its founders built an in-house ERP for their
own hardware business, first known as Wawision, later Xentral, released as
open-source software under the EGPL v3.1 license. In 2017 they wound down the
hardware side and focused entirely on the ERP. Over the following years the
product moved to a proprietary, cloud-only SaaS model, and the open-source
edition was left behind. Today Xentral markets itself as a cloud-native ERP for
small and mid-size commerce in the DACH region.

Sources. [Xentral on Wikipedia](https://en.wikipedia.org/wiki/Xentral_ERP_Software),
[Who is Xentral](https://xentral.com/en/we-are-xentral),
[Xentral ERP product page](https://xentral.com/en/erp).

## 2. Modern Xentral is cloud-only in 2026

Verified against current sources. Xentral ships only as a cloud SaaS product.
There is no download, no on-premise edition, and no paid self-hosted tier. One
older third-party listing still mentions on-premise, but that entry is stale.
Every current source agrees the product is cloud only.

Sources. [Xentral ERP](https://xentral.com/en/erp),
[Capterra 2026](https://www.capterra.com/p/185775/Xentral-Software/),
[G2 2026](https://www.g2.com/products/xentral-erp/reviews).

## 3. The only self-hostable Xentral is OpenXE, and it is the old one

When Xentral went closed and cloud-only, the last open-source version lived on as
community forks. The most active is OpenXE, still maintained, licensed EGPL. It
is a real, working PHP and MariaDB ERP you can run on your own server. It is also,
by definition, the previous generation of the code. Two other forks exist,
Xenomporio and an older offline installer, both less active.

Sources. [OpenXE](https://github.com/OpenXE-org/OpenXE),
[Xenomporio](https://github.com/OpenXE-org/Xenomporio-forked-from-xentral),
[XentralOpenSource offline installer](https://github.com/AlexLedis/XentralOpenSource),
[a community Docker image](https://github.com/lobaro/xentral-docker).

## 4. The reason it all fails. two API generations that do not meet

This is the load-bearing fact. OpenXE and modern Xentral do not share an API.

| | OpenXE, self-hostable | Modern Xentral, cloud |
|---|---|---|
| Where it runs | Your own server | Xentral SaaS only |
| API authentication | HTTP Digest | Bearer Personal Access Token |
| Where API credentials are made | Admin UI, Settings, API Accounts | Xentral admin, Developer Settings, Personal Access Tokens |
| Endpoint shape | old community API | v1, v2, v3 REST |
| Talks to a modern Xentral MCP | No | Yes |
| Generation | Previous | Current |

A modern connector attaches a Bearer token and calls the modern v1, v2, and v3
paths. OpenXE answers a different API with a completely different authentication
method. No environment variable, base URL, or flag bridges that. It is not a
configuration gap. It is a different product era.

## 5. If you still want to run OpenXE, on any host

OpenXE is a fine sandbox if you simply want an ERP you own to click around in. It
is a standard PHP and MariaDB app in Docker, so it runs on any Linux server from
any provider. Nothing in this recipe is tied to a particular host or a particular
DNS or TLS setup. A small virtual server anywhere is enough, for example
DigitalOcean, Linode or Akamai, Vultr, Scaleway, Hetzner, OVH, IONOS, Contabo,
AWS (Lightsail or EC2), Google Cloud, Azure, Oracle Cloud free tier, or a box
under your own desk. The steps are the same on all of them.

The full, sanitized recipe is in [scripts/deploy-openxe.sh](scripts/deploy-openxe.sh).
The parts that cost real time are called out below so you do not lose them the
way this experiment did. Two of them are universal to OpenXE on any host, and the
last one is only about pointing a domain at the box, which also works the same
everywhere.

### Trap 1. the base image drifted from Debian 12 to Debian 13

The `php:8.1-apache` base image moved to Debian 13 (trixie), but the OpenXE
Dockerfile pins Debian 12 (bookworm) package versions that no longer resolve on
trixie. The build fails at the apt step with several missing runtime libraries,
for example the IMAP, AVIF, dav1d, and zip libraries. The fix is one line. pin
the web server stage of the Dockerfile to the bookworm variant,
`php:8.1-apache-bookworm`, where all the pinned packages exist. After that the
build and the database migration complete cleanly.

### Trap 2. the admin login uses passwordhash, not password

A headless install skips the web setup wizard, so the default `admin` account has
no usable password. The login verifies against a `passwordhash` column that holds
a bcrypt hash, not the legacy `password` column that a naive fix would set. On a
correct old-style login OpenXE even migrates the old value into `passwordhash` and
clears the legacy fields. So the working fix is to set `passwordhash` to a bcrypt
of your chosen password and clear the legacy columns. Set the account email on the
linked address row, not the user row, because the user record points at an address
id where the email lives.

### Getting it onto a domain, the same on any provider

Putting the box on a real domain with HTTPS is two steps, and they are identical no
matter who hosts the server or who runs your DNS.

1. Point a DNS A record for your subdomain at the server's public IP address. Any
   DNS provider works, whether that is your domain registrar, the hosting company's
   own DNS, or a service such as Cloudflare or Route 53.
2. Run a reverse proxy on the box that obtains a free TLS certificate
   automatically. Caddy does this in a few lines, and nginx with certbot, or
   Traefik, do the same. Any of them works on any host.

That is the whole story on every provider. Two warnings from this experiment so you
skip the detours they cost, and neither is an OpenXE problem. First, do not try to
route the domain through a serverless edge function that fetches the origin box. On
one such platform that specific attempt fails outright, and it is the wrong shape
regardless of the platform. Second, a plain command-line login token from a DNS or
edge provider may not carry permission to write DNS records, so create the record
in the provider dashboard or with an API token that has DNS edit rights.

## 6. The cost angle

A box large enough for a single-user OpenXE runs on the order of a few euros a
month. Small, but not zero, and pure waste if the box cannot serve its purpose.
Idle infrastructure that exists only to prove a point should be deleted the moment
it has proven it. The box built for this experiment was torn down after it
confirmed the finding.

## 7. The verdict. not worth building on

Not worth it, for a modern integration goal. The self-hosted OpenXE box was a
sandbox, not a foundation. It could not serve a modern connector, its users are
not the audience that runs modern Xentral, and every hour spent on it compounds on
the old generation. If your reason for self-hosting was to develop or test against
Xentral, that reason is void, because the thing you can self-host is the wrong
generation.

## 8. What to do instead

- You want to build or use a modern Xentral integration. Get a modern Xentral
  cloud account, create a Personal Access Token in Developer Settings, and point
  your connector at it. That is the only path that works.
- You want to own a self-hosted ERP for its own sake. OpenXE is fine, run it, but
  do not expect it to connect to anything built for modern Xentral.
- You want self-hosted and modern together. That is not Xentral. Look at a modern
  self-hostable ERP such as [ERPNext](https://frappe.io/erpnext) or
  [Odoo Community](https://www.odoo.com/), each with its own API and its own
  connector. Different product, different integration.

There is no option that is self-hosted, modern, and Xentral at the same time. That
combination does not exist in the market as of 2026.

## References

- Xentral, company and history. https://xentral.com/en/we-are-xentral
- Xentral on Wikipedia. https://en.wikipedia.org/wiki/Xentral_ERP_Software
- Xentral ERP product page, cloud positioning. https://xentral.com/en/erp
- Xentral on Capterra, 2026. https://www.capterra.com/p/185775/Xentral-Software/
- Xentral on G2, 2026. https://www.g2.com/products/xentral-erp/reviews
- OpenXE, the maintained fork. https://github.com/OpenXE-org/OpenXE
- Xenomporio fork. https://github.com/OpenXE-org/Xenomporio-forked-from-xentral
- XentralOpenSource offline installer. https://github.com/AlexLedis/XentralOpenSource
- A community Docker image for the old Xentral. https://github.com/lobaro/xentral-docker
- ERPNext, a modern self-hostable ERP. https://frappe.io/erpnext
- Odoo, a modern self-hostable ERP. https://www.odoo.com/

## Trademarks and independence

"Xentral" and the Xentral name, logo, and brand belong to their owner and are not
the property of the author of these notes. This project is an independent record.
It is not affiliated with, endorsed by, or supported by Xentral. Every reference to
Xentral here is nominative and used only to describe the facts. Names such as
OpenXE, Cloudflare, Caddy, Docker, ERPNext, and Odoo are the property of their
respective owners.

## License

These notes and the script are shared under Creative Commons Attribution 4.0
(CC BY 4.0). Use them, quote them, build on them, with credit to the author and a
link back to this repository. See [LICENSE](LICENSE). Provided as is, with no
warranty, and no responsibility for what you do with them.
