#!/usr/bin/env nix-shell
#! nix-shell -i bash
#! nix-shell -p bash
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/2ea61d0eb4f829f8e2e905f0be681a5138d519c9.tar.gz

set -e

function deploy() {
	echo ::: Creating topology

	declare -A addrs
	for node in rr client0 client1 external; do
		docker run -d --rm --privileged \
			-v $(pwd)/config/daemons:/etc/frr/daemons \
			-v $(pwd)/config/${node}.conf:/etc/frr/frr.conf \
			--name ${node} \
			frrouting/frr:latest
		addrs[${node}]=$(docker inspect ${node} -f '{{.NetworkSettings.Networks.bridge.IPAddress}}')
	done

	echo "::: Waiting for 5s for startup"
	sleep 5

	echo "::: Setting up rr"
	docker exec rr ip addr add 10.0.0.0/24 dev lo
	docker exec rr vtysh \
		-c "conf t" \
		-c "router bgp 65000" \
		-c "neighbor ${addrs[client0]} peer-group CLIENTS" \
		-c "neighbor ${addrs[client1]} peer-group CLIENTS" \
		-c "neighbor ${addrs[external]} peer-group EBGP_PEERS"

	echo "::: Setting up client0"
	docker exec client0 ip addr add 10.0.1.0/24 dev lo
	docker exec client0 vtysh \
		-c "conf t" \
		-c "router bgp 65000" \
		-c "neighbor ${addrs[rr]} peer-group ROUTE_REFLECTORS"

	echo "::: Setting up client1"
	docker exec client1 ip addr add 10.0.2.0/24 dev lo
	docker exec client1 vtysh \
		-c "conf t" \
		-c "router bgp 65000" \
		-c "neighbor ${addrs[rr]} peer-group ROUTE_REFLECTORS"

	echo "::: Setting up external"
	docker exec external vtysh \
		-c "conf t" \
		-c "router bgp 65001" \
		-c "neighbor ${addrs[rr]} peer-group EBGP_PEERS"
}

function destroy() {
	for node in rr client0 client1 external; do
		docker kill ${node}
	done
}

function smoke_test() {
	echo "::: Pinging rr"
	docker exec external traceroute 10.0.0.1
	echo ""
	echo "::: Pinging client0"
	docker exec external traceroute 10.0.1.1
	echo ""
	echo "::: Pinging client1"
	docker exec external traceroute 10.0.2.1
	echo ""
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
