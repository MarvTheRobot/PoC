<#
    PoC the ability to visualise Azure Virtual Network relationships via VirtualNetworkPeering. 

    GraphViz (https://graphviz.org) and PSGraph (https://github.com/KevinMarquette/PSGraph) are used for the visualisations
#>

#Set some defaults
$defaults = @{
    ResourceGroupName = "PoC-NetworkPeeringGraph"
    Location = "UK South"
}

#Define some network information
$networkMap = @{
    "network-a" = @{
        AddressPrefix = "10.0.0.0/24"
        Subnets = @{
            "subnet-a" = @{ AddressPrefix = "10.0.0.0/24" }
        }
        Peerings = @{
            "peering-to-b" = @{ TargetNetwork = "network-b" }
        }   
    }
    "network-b" = @{
        AddressPrefix = "10.0.1.0/24"
        Subnets = @{
            "subnet-a" = @{ AddressPrefix = "10.0.1.0/24" }
        }
        Peerings = @{
            "peering-to-a" = @{ TargetNetwork = "network-a"}
            "peering-to-c" = @{ TargetNetwork = "network-c"}
        }   
    }
    "network-d" = @{
        AddressPrefix = "10.0.4.0/24" 
        Subnets = @{
            "subnet-a" = @{ AddressPrefix = "10.0.4.0/24"}
        }
        Peerings = @{
        }   
    }
    "network-e" = @{
        AddressPrefix = "10.0.5.0/24" 
        Subnets = @{
            "subnet-a" = @{ AddressPrefix = "10.0.5.0/24"}
        }
        Peerings = @{
            "peering-to-a" = @{ TargetNetwork = "network-a"}
            "peering-to-b" = @{ TargetNetwork = "network-b"}
            "peering-to-c" = @{ TargetNetwork = "network-c"}
            "peering-to-f" = @{ TargetNetwork = "network-f"}
        }   
    }
    "network-f" = @{
        AddressPrefix = "10.0.6.0/24" 
        Subnets = @{
            "subnet-a" = @{ AddressPrefix = "10.0.6.0/24"}
        }
        Peerings = @{
            "peering-to-e" = @{ TargetNetwork = "network-e"}
        }   
    }
}
#Set-AzContext -Subscription 'some guid'
$deploymentType = "Proof of Concept"
$useCase = "As a Network Operator,
I need a way to visualise Azure Virtual Networks and their relationships, via peering, to one another,
so that I can support a large the various deployed virtual networks for the organsiation"

New-AzResourceGroup -Name $defaults.ResourceGroupName -Location $defaults.Location -Tag @{DeploymentType = $deploymentType; UseCase = $useCase} -Force

$createNetworks = {
    foreach ($network in $networkMap.Keys){
        $properties = @{
            Name = $network
            AddressPrefix = $networkMap.$network.AddressPrefix
            ResourceGroupName = $defaults.ResourceGroupName
            Location = $defaults.Location
            Subnet = foreach($subnet in $networkMap.$network.Subnets.Keys){
                Write-Information "Creating subnet configuration for subnet '$subnet', in network '$network'" -InformationAction Continue
                New-AzVirtualNetworkSubnetConfig -Name $subnet -AddressPrefix $networkMap.$network.Subnets.$subnet.AddressPrefix
            }
        }

        New-AzVirtualNetwork @properties -force
    }
}

$createPeerings = {
    $deployedNetworks = Get-AzVirtualNetwork

    foreach ($deployedNetwork in $deployedNetworks){
        $deployedNetworkName  = $deployedNetwork.Name
        $mappedNetwork        = $networkMap.$deployedNetworkName
        $requiredPeeringNames = $mappedNetwork.Peerings.Keys
        
        foreach($peeringName in $requiredPeeringNames){
            $props = @{
                Name = $peeringName
                VirtualNetwork = $deployedNetwork
                RemoteVirtualNetworkId =  ($deployedNetworks | where-object {$_.Name -eq $mappedNetwork.Peerings.$peeringName.TargetNetwork}).Id
            }
            Add-AzVirtualNetworkPeering @props -EA SilentlyContinue | Out-Null
        }
    }
}

$visualise = {
    $deployedNetworks = Get-AzVirtualNetwork | select-object Id, Name, VirtualNetworkPeerings

    $networkMap = foreach($network in $deployedNetworks){
        $props = @{
            network  = $network.Name
            peerings = foreach($peering in $network.VirtualNetworkPeerings.GetEnumerator()){
                ($deployedNetworks | ? {$_.Id -eq $peering.RemoteVirtualNetwork.Id}).Name
            }
        }
        New-Object -TypeName PsObject -Property $props
    }

    graph g {
        $networkMap.Network | % {node $_}
        $networkMap | % {
            $localNetwork = $_.Network
            $_.Peerings | % {
                edge $localNetwork $_
            }
        }
    }| Export-PSGraph -ShowGraph

}

& $createNetworks
& $createPeerings
& $visualise