# CiliumLoadBalancerIPPool - Generated from config.yaml
# Do not edit directly - run: make generate-network-config
#
# Network allocation (VLAN {{VLAN}} - {{SUBNET}}):
# - Static hosts: .1-.127
# - DHCP pool: .128-.191
# - LoadBalancer VIPs: {{LB_START}}-{{LB_STOP_LAST_OCTET}} (this pool)
# - Reserved: .224-.254
---
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: {{LB_POOL_NAME}}
spec:
  allowFirstLastIPs: "No"
  blocks:
    - cidr: "{{LB_RANGE}}"
  serviceSelector:
    matchExpressions:
    - key: lb.cilium.io/pool
      operator: In
      values: ["apps"]
