#!/usr/bin/env nix-shell
#! nix-shell -i bash
#! nix-shell -p bash kind cilium-cli kubectl kubernetes-helm
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/2ea61d0eb4f829f8e2e905f0be681a5138d519c9.tar.gz

function deploy() {
	echo Create Kind cluster and install Cilium
	kind create cluster --config cluster.yaml
	cilium install \
		--set ingressController.enabled=true \
		--set ingressController.loadbalancerMode=dedicated \
		--set ingressController.default=true \
		--set kubeProxyReplacement=true \
		--set l2announcements.enabled=true
	cilium status --wait

	echo Wait for cilium-operator to install CRDs
	sleep 5

	echo Generate CA certificate
	openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -days 3650 -nodes -keyout ca.key -out ca.crt -subj "/CN=ExampleCA"
	kubectl create secret tls ca-secret --cert=ca.crt --key=ca.key
	rm ca.crt ca.key

	echo Install cert-manager
	helm install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--set crds.enabled=true \
		--wait

	echo Apply all resources
	kubectl apply -f resources.yaml

	echo Provision client container
	lbip=$(kubectl get ingress httpbin -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
	docker run -d --name cert-manager-cilium-client --privileged --rm --net kind nicolaka/netshoot:latest sleep infinite
	docker exec -it cert-manager-cilium-client ip route add $lbip/32 dev eth0
}

function destroy() {
	kind delete clusters cert-manager-cilium
	docker kill cert-manager-cilium-client
}

function smoke_test() {
	lbip=$(kubectl get ingress httpbin -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
	docker exec -it cert-manager-cilium-client \
		curl -vk --resolve example.example.com:443:$lbip \
			--retry 10 --retry-delay 1 \
			https://example.example.com/get
}

case "$1" in
	deploy)
		deploy
		;;
	destroy)
		destroy
		;;
	smoke_test)
		smoke_test
		;;
	*)
		echo "Unknown command $1"
		;;
esac
