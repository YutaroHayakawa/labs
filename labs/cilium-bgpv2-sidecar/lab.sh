#!/usr/bin/env nix-shell
#! nix-shell -i bash
#! nix-shell -p bash kind cilium-cli kubectl containerlab
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/2ea61d0eb4f829f8e2e905f0be681a5138d519c9.tar.gz

function deploy() {
	echo ::: Create Kind cluster and ContinerLab topology
	kind create cluster --config cluster.yaml
	sudo containerlab -t topo.yaml deploy

	echo ::: Install Cilium
	cilium install \
		--version "1.17.0-pre.3" \
		--set kubeProxyReplacement=true \
		--set bgpControlPlane.enabled=true
	cilium status --wait --interactive=false

	echo ::: Wait for cilium-operator to install CRDs
	sleep 5

	echo ::: Apply all resources
	kubectl apply -f resources.yaml
}

function destroy() {
	sudo containerlab -t topo.yaml destroy
	kind delete clusters cilium-bgpv2-sidecar
}

function smoke_test() {
	pod_cidr_routes=$( \
		docker exec -it clab-cilium-bgpv2-sidecar-router0 \
		vtysh -c "show bgp ipv4 unicast detail json" | \
		jq '[select(.routes.[].[].largeCommunity.string == "8:1:0")] | length'
	)
	svc_routes=$( \
		docker exec -it clab-cilium-bgpv2-sidecar-router0 \
		vtysh -c "show bgp ipv4 unicast detail json" | \
		jq '[select(.routes.[].[].largeCommunity.string == "8:2:0")] | length'
	)
	if [ $pod_cidr_routes != 2 ]; then
		exit 1
	fi
	if [ $svc_routes != 2 ]; then
		exit 1
	fi
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
		echo "::: Unknown command $1"
		;;
esac
