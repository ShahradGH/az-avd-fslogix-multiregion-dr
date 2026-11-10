param location string = 'ukwest'
resource sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'stfslogixprofukw01'
  location: location
  sku: { name: 'Premium_ZRS' }
  kind: 'FileStorage'
}
