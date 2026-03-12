---
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: advertise-lb-prod
  labels:
    advertise: "bgp"
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - key: lb.cilium.io/pool
            operator: In
            values: ["apps"]