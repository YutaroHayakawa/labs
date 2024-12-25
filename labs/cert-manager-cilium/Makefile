CILIUM_VERSION ?= v1.16.5
CERTMANAGER_VERSION ?= v1.16.2

deploy:
	@echo Creating Kind cluster and install Cilium
	kind create cluster --config cluster.yaml
	cilium install \
		--version $(CILIUM_VERSION) \
		--set ingressController.enabled=true \
		--set ingressController.loadbalancerMode=dedicated \
		--set ingressController.default=true \
		--set kubeProxyReplacement=true \
		--set l2announcements.enabled=true
	cilium status --wait
	@echo Waiting for cilium-operator to install CRDs
	sleep 5
	@echo Generating CA certificate
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -days 3650 -nodes -keyout ca.key -out ca.crt -subj "/CN=ExampleCA"
	kubectl create secret tls ca-secret --cert=ca.crt --key=ca.key
	rm ca.crt ca.key
	@echo Install cert-manager
	helm install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version $(CERTMANAGER_VERSION) \
		--set crds.enabled=true \
		--wait
	@echo Applying all resources
	kubectl apply -f resources.yaml
	@echo Provisioning client container
	docker run -d --name cert-manager-cilium-client --privileged --rm --net kind nicolaka/netshoot:latest sleep infinite
	docker exec -it cert-manager-cilium-client ip route add `kubectl get ingress httpbin -o jsonpath="{.status.loadBalancer.ingress[0].ip}")`/32 dev eth0

destroy:
	kind delete clusters cert-manager-cilium
	docker kill cert-manager-cilium-client

test:
	docker exec -it cert-manager-cilium-client \
		curl -vk --resolve example.example.com:443:`kubectl get ingress httpbin -o jsonpath="{.status.loadBalancer.ingress[0].ip}")` \
			--retry 10 --retry-delay 1 \
			https://example.example.com/get
