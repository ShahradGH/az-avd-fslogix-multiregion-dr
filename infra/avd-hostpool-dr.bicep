param location string = 'ukwest'
resource hp 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: 'vdpool-standby-ukw'
  location: location
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'Desktop'
  }
}
