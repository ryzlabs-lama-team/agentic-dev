---
name: azure-cloud
description: Routes Azure work to the matching reference skill in "../../skills-library/azure/". Use whenever a task touches an Azure service — Functions, Blob or Queue Storage, Cosmos DB, SQL Database, Key Vault, Document Intelligence, Content Understanding, Microsoft Foundry, API Management, Application Gateway, Virtual Network, Private Link, RBAC, App Configuration, Deployment Environments, security, or solution architecture — before answering Azure questions from memory or writing Azure code, Bicep, or Terraform.
---

# Azure Cloud

`../../skills-library/azure/` holds Microsoft-generated reference skills, one per Azure service. They are a library, not auto-loaded context: nothing reaches you until you read it. This skill decides which one to open.

Each reference skill is a curated index of `learn.microsoft.com` URLs grouped by category, not prose you can answer from directly. The index tells you which page answers the question; you still fetch the page.

## Procedure

1. Match the task against the routing table below. More than one row can apply — a Function writing to Blob Storage behind a private endpoint is three.
2. Read the first ~40 lines of `../../skills-library/azure/<skill>/SKILL.md`. That is the frontmatter plus the **Category Index** table, which maps each category to a line range or a companion file.
3. Read only the line ranges the task needs. These files run 8 KB to 128 KB; reading one whole wastes the context the task needs.
4. Fetch the URLs that matter. Use a Microsoft Docs MCP tool if one is configured; otherwise fetch the URL directly, appending `?from=learn-agent-skill&accept=text/markdown` to get Markdown back. The skills name `mcp_microsoftdocs:microsoft_docs_fetch` and `fetch_webpage` — those are VS Code tool names; use this runtime's equivalents.
5. Ground the answer in what you fetched. Cite the URL when it settles a version, limit, or quota.

`azure-cosmos-db` splits its larger categories into companion files (`configuration.md`, `deployment.md`, `integrations.md`) next to its `SKILL.md`. Every other skill is a single file.

## Routing table

| Read this skill | When the task involves |
|---|---|
| `azure-functions` | Triggers and bindings, isolated worker model, host.json, Durable Functions, Flex Consumption vs Premium, cold start, scaling limits, `local.settings.json`, deployment slots |
| `azure-blob-storage` | Containers, access tiers, lifecycle policies, SAS tokens, blob leases, `BlobClient` SDK usage, upload/download performance, immutability and soft delete |
| `azure-queue-storage` | Storage queues, visibility timeout, poison messages, dequeue counts, queue SDK patterns. Service Bus is a different service and has no skill here |
| `azure-document-intelligence` | Prebuilt and custom extraction models, `AnalyzeDocument`, layout vs read vs custom, confidence scores, training sets, v4.0 API and migration from v3.x |
| `azure-content-understanding` | Multimodal analyzers and classifiers, Markdown output for RAG, audio/video analysis, schema-driven field extraction |
| `microsoft-foundry` | Foundry projects and agents, Azure OpenAI model deployments, AI Gateway, Foundry IQ retrieval, Entra-authenticated inference |
| `azure-sql-database` | T-SQL against Azure SQL, EF Core provider behavior, DTU vs vCore, serverless auto-pause, Hyperscale, geo-replication, elastic pools, connection resiliency |
| `azure-cosmos-db` | Partition key design, RU provisioning and throttling, change feed, consistency levels, SQL/Mongo/Cassandra APIs, multi-region writes, vector search |
| `azure-key-vault` | Secrets, keys and certificates, rotation, soft delete and purge protection, RBAC vs access policies, referencing vault secrets from app settings |
| `azure-app-configuration` | Centralized settings, feature flags, labels, snapshots, dynamic refresh, `Microsoft.Extensions.Configuration` providers |
| `azure-rbac` | Role assignments, built-in vs custom roles, scope inheritance, ABAC conditions, managed identity permissions, PIM, `roleDefinition` JSON |
| `azure-security` | Encryption at rest, customer-managed keys, Customer Lockbox, image and supply-chain hardening, sovereign cloud constraints |
| `azure-virtual-network` | VNets and subnets, NSG rules, peering, service endpoints, subnet delegation, egress and public IP behavior |
| `azure-private-link` | Private endpoints, private DNS zones and resolvers, Network Security Perimeter, locking a PaaS resource off the public internet |
| `azure-application-gateway` | Listeners, routing rules, backend pools, WAF policies, TLS termination and end-to-end TLS, health probes, autoscaling |
| `azure-api-management` | API gateways and products, policy expressions, subscription keys, OAuth/Entra validation, self-hosted gateways, versioning and revisions |
| `azure-deployment-environments` | ADE catalogs, environment types, project-level RBAC, environment definitions driven from CI/CD |
| `azure-architecture` | Design-level decisions before a service is chosen: reference architectures, Well-Architected trade-offs, design patterns, anti-patterns, DR and multi-region topology |

## When nothing matches

The library covers 18 services, not all of Azure. Service Bus, Event Grid, Container Apps, App Service, Front Door, Monitor and Application Insights have no skill here.

For those, say the library does not cover it and fetch `learn.microsoft.com` directly, or ask. Do not substitute a neighbouring skill — Queue Storage guidance is wrong for Service Bus — and do not answer from memory on versions, limits, quotas, or API shapes. Those are exactly what drifts.

If a skill's `metadata.generated_at` is more than three months behind today's date, treat its URL list as a starting point rather than current, and say so.
