#MigrateWebApps
#2023.08.27 JPot
#prof-it.services

$region = ""

$rgnorg = 'AppS'
$rgntemp = 'AppSM'

$appserviceplanorg = "AppServicePlan"
$appserviceplannew = "AppServicePlanM"
$appserviceplantemp = "AppServicePlanT"

#VNet Specs for all sites
$VNetRGN= "VNetRGN"
$vNetName = 'vnet'
$integrationSubnetName = 'new_subnet'
$subscriptionId = ''
$subnetResourceId = "/subscriptions/$subscriptionId/resourceGroups/$VNetRGN/providers/Microsoft.Network/virtualNetworks/$vNetName/subnets/$integrationSubnetName"

$sites = Get-AzWebApp -ResourceGroupName $rgnorg
$count = 0

#CLONING, in batches of 10 sites
foreach ($site in $sites)
{
  if ($count -ge 10) {
    break
  }

  if (!($site.ServerFarmId.EndsWith($appserviceplanorg))) {
    continue
  }

  $tempname = "TEMP-$($site.Name)"

  try {  
    write-output "$($site.Name) - Cloning original to temp site"
    New-AzWebApp -ResourceGroupName $rgntemp -Name $tempname -Location $region -AppServicePlan $appserviceplantemp -SourceWebApp $site
  }
  catch {
    throw "$($site.Name) - error cloning"
  }
  $count = $count + 1
}

write-output "Done. Pausing for 10 minutes."
Start-Sleep -Seconds 600

#GET TEMP SITES
$tempsites = Get-AzWebApp -ResourceGroupName $rgntemp

#REMOVE ORIGINAL, based on cloned TEMP sites
foreach($site in $tempsites)
{
  if (!($site.ServerFarmId.EndsWith($appserviceplantemp))) {
    continue
  }

  if (!($site.Name.Contains("TEMP-"))) {
    continue
  }
  $siteorgname = $site.Name.Split("TEMP-")[1]

  try {
    write-output "$($site.Name) - Removing original site"
    $orgsite = Get-AzWebApp -ResourceGroupName $rgnorg -Name $siteorgname
    $orgsite | Remove-AzWebApp  -Force
  }
  catch {
    throw "$($site.Name) - error removing original"

  }
}

write-output "Done. Pausing for 10 minutes."
Start-Sleep -Seconds 600

#RESTORE SITES
foreach($site in $tempsites)
{
    if (!($site.ServerFarmId.EndsWith($appserviceplantemp))) {
      continue
    }
    
    if (!($site.Name.Contains("TEMP-"))) {
      continue
    }

    $siteorgname = $site.Name.Split("TEMP-")[1]

    write-output "$($site.Name) - Restoring clone to original site"
    New-AzWebApp -ResourceGroupName $rgnorg -Name $siteorgname -Location $region -AppServicePlan $appserviceplannew -SourceWebApp $site

    Write-Output "$($site.Name) - Restoring network integration"
    $sitenew = Get-AzResource -ResourceType Microsoft.Web/sites -ResourceGroupName $rgnorg -ResourceName $siteorgname
    $sitenew.Properties.virtualNetworkSubnetId = $subnetResourceId
    $sitenew | Set-AzResource -Force
}


write-output "Done. Pausing for 10 minutes."
Start-Sleep -Seconds 600

#DELETE TEMP Sites
foreach($site in $tempsites)
{
  if (!($site.ServerFarmId.EndsWith($appserviceplantemp))) {
    continue
  }

  if (!($site.Name.Contains("TEMP-"))) {
    continue
  }

  $siteorgname = $site.Name.Split("TEMP-")[1]

  try {
    if (!(Get-AzResource -ResourceType Microsoft.Web/sites -ResourceGroupName $rgnorg -ResourceName $siteorgname)) {
        Write-Output "$($site.Name) - new site not found"
        pause
    } else {
        write-output "$($site.Name) - Removing temp site"
        $site | Remove-AzWebApp -Force
    }
  }
  catch {
    throw "$($site.Name) - error removing temp site"
  }
}
