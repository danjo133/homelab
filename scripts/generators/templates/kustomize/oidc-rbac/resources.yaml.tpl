# Auto-generated from cluster.yaml — do not edit
# Custom ClusterRole for k8s-operators: read-only access to operational resources
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-operator
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - events
      - namespaces
      - configmaps
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
---
# Auto-generated from cluster.yaml — do not edit
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-platform-admins
subjects:
  - kind: Group
    name: "oidc:platform-admins"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
# Auto-generated from cluster.yaml — do not edit
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-k8s-admins
subjects:
  - kind: Group
    name: "oidc:k8s-admins"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
# Auto-generated from cluster.yaml — do not edit
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-k8s-operators
subjects:
  - kind: Group
    name: "oidc:k8s-operators"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: k8s-operator
  apiGroup: rbac.authorization.k8s.io
