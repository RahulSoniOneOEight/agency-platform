library;

// Public boundary: the deterministic fake adapters and the scenario enum.
// No provider client, transport, or vendor type is exported — every failure
// crosses this boundary as a provider-neutral `DomainFailure`.
export 'src/fake/fake_crm_adapter.dart';
export 'src/fake/fake_erp_adapter.dart';
export 'src/fake/fake_integration_scenario.dart';
export 'src/fake/fake_payment_adapter.dart';
export 'src/fake/fake_shipping_adapter.dart';
export 'src/fake/fake_whatsapp_adapter.dart';
