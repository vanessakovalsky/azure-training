# Glossary — Microsoft Azure administration (AZ-104)

One term per line, with the module where it is covered. Alphabetical order.

| Term | Definition | Module |
|---|---|---|
| Access tier lifecycle | Rules moving blobs between tiers or deleting them based on age | M6 |
| ACI (Azure Container Instances) | Runs a container with no cluster or VM to manage | M8 |
| ACR (Azure Container Registry) | Private container image registry; image builds with ACR Tasks | M8 |
| Action group | Recipients and actions of an alert (email, SMS, webhook…) | M10 |
| Administrative unit (AU) | Entra ID scope to delegate administration of part of the users and groups | M1 |
| AKS (Azure Kubernetes Service) | Managed Kubernetes: control plane managed by Azure | M8 |
| Alert | Rule = scope + signal + condition + action group; severity Sev0 to Sev4 | M10 |
| App Service | PaaS hosting for web apps; capacity provided by an App Service plan | M8 |
| App Service plan | Compute capacity and feature level of App Service; billing unit | M8 |
| ARM (Azure Resource Manager) | Azure deployment and management layer; declarative JSON templates | M3 |
| ASG (Application Security Group) | Logical group of NICs, usable as source or destination in an NSG rule | M4 |
| Availability set | Spreads VMs across fault and update domains within one datacenter | M7 |
| Availability zone | Isolated datacenter(s) in a region; restrictions may apply per subscription | M7 |
| Azure Files | Managed SMB / NFS file shares in a storage account | M6 |
| Azure File Sync | Sync between a Windows server and an Azure Files share, with tiering | M6 |
| Azure Firewall | Managed stateful firewall with network and application rules, logging | M4 |
| Azure Monitor agent (AMA) | Guest OS collection agent, driven by data collection rules (DCR) | M7, M10 |
| Azure Policy | Compliance evaluation service that can deny non-compliant resources | M2 |
| Bastion | RDP / SSH access to VMs from the portal, no public IP on the VMs | M7 |
| Bicep | Declarative language compiled to an ARM template; idempotent | M3 |
| Blob versioning | Automatic retention of previous versions of a blob | M6 |
| Budget | Cost threshold with alerts; stops no resource | M2 |
| Cloud-init | Linux VM configuration at first boot (custom data) | M7 |
| Cloud Shell | Browser-based Bash / PowerShell terminal with Azure tools preinstalled | M0, M3 |
| Cloud tiering | File Sync: rarely used files replaced by pointers on the server | M6 |
| Conditional Access | Entra ID access rules based on user, device, location, risk (P1 licence) | M1 |
| DCR (data collection rule) | What the Azure Monitor agent collects and where it sends it | M7, M10 |
| Deployment slot | Copy of an App Service app; zero-downtime swap | M8 |
| Dynamic group | Membership computed by a rule on attributes (P1 licence) | M1 |
| Entra ID (formerly Azure AD) | Microsoft identity service: users, groups, applications | M1 |
| ExpressRoute | Private carrier link to Azure, no Internet transit | M5 |
| Gateway transit | A spoke using the hub VPN gateway through peering | M5 |
| Geo-redundancy (GRS / RA-GRS) | Asynchronous copy to the paired region; RA = read access to the secondary | M6 |
| Guest (B2B) | External user invited into the tenant | M1 |
| Hub-spoke | Topology: shared central network (firewall, gateway) peered with application networks | M4 |
| KQL (Kusto Query Language) | Query language of Log Analytics | M10 |
| Least privilege | Assign the minimal role at the minimal scope | M2 |
| Load Balancer | Layer-4 (TCP / UDP) load balancing, public or internal | M7 |
| Local network gateway | Representation of the remote site (public IP, ranges) for a VPN | M5 |
| Log Analytics workspace | Log store queried with KQL; retention and cost per GB | M3, M10 |
| Managed disk | VM disk managed by Azure (HDD, Standard SSD, Premium SSD, Ultra) | M7 |
| Managed identity | Entra ID identity of an Azure resource, no secret to manage | M6, M8 |
| Management group | Level above subscriptions for policies and RBAC | M2 |
| MARS agent | Microsoft Azure Recovery Services agent: file backup of a server | M9 |
| NAT gateway | Explicit, fixed-IP Internet egress for a subnet | M6, M7 |
| Network Watcher | Network diagnostic tools: next hop, IP flow verify, flow logs | M10 |
| NSG (Network Security Group) | Inbound / outbound filtering rules on a subnet or a NIC | M4 |
| Object replication | Asynchronous copy of blobs between two accounts | M6 |
| Paired region | Backup region designated by Microsoft for geo-replication | M6 |
| Peering | Private link between two virtual networks; non-transitive | M5 |
| Policy assignment | Application of an Azure Policy definition to a scope, with parameters | M2 |
| Private DNS zone | Name resolution internal to the linked virtual networks | M4, M6 |
| Private endpoint | Private NIC of a PaaS service in a customer subnet | M6 |
| Public network access (storage) | Internet endpoint of a storage account; can be disabled in favour of a private endpoint | M6 |
| RBAC (Azure) | Role-based access control: principal + role + scope | M2 |
| Recovery point | Restorable state of a backed-up resource (snapshot or vault) | M9 |
| Recovery Services vault | Backup vault for VMs, Azure Files and the MARS agent | M9 |
| Resource group | Logical container of resources sharing a lifecycle | M2 |
| RPO / RTO | Maximum acceptable data loss / maximum acceptable downtime | M9 |
| SAS (shared access signature) | Delegated access token, limited in rights and duration; account, service or user delegation | M6 |
| Scope | Level where a role or policy applies: management group, subscription, resource group, resource | M2 |
| Site Recovery | Replication and failover of VMs to another region | M9 |
| Soft delete | Temporary retention of deleted blobs, containers or backup items | M6, M9 |
| SSPR | Self-service password reset | M1 |
| Storage account | Unique namespace for blobs, files, queues and tables | M6 |
| Subscription | Billing unit and quota boundary; contains resource groups | M2 |
| Tag | Key / value pair on a resource or group: costs, owner, environment | M2 |
| UDR (user-defined route) | Custom route in a route table, e.g. `0.0.0.0/0` to the firewall | M4 |
| Virtual WAN | Managed wide-area network service (Microsoft hubs, VPN, ExpressRoute) | M5 |
| VM extension | Agent running inside the VM (Custom Script, Azure Monitor, etc.) | M7 |
| VMSS (scale set) | Set of identical VMs with autoscale | M7 |
| VNet (virtual network) | Isolated private network in a region, divided into subnets | M4 |
| VPN gateway | Virtual network gateway for site-to-site or point-to-site IPsec tunnels | M5 |
