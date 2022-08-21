# spot-eks-tf

resources:

- eks cluster
	- node groups
		- spot node group * 2
		- on-demand node group 
	- node role
	- cluster service role

- vpc
	- security group
	
	- routing tables
		- public
		- private
	
	- 2 zones
		- subnets
			- public
				- internet gw
			- private
				- nat gateway
					- elastic ip

todo:
* node pools optimization (zones * pools)
* node allocation type label (spot / on-demand)
* allocation-strategy for spot nodes (ex: capacity-optimized)
* node termination handler for spot nodes
* cluster auto-scaler
	* expander=random, balance-similar-node-groups, skip-nodes-with-system-pods=false, skip-nodes-with-local-storage=false
			 





