import 'package:deepbook/client.dart';
import 'package:deepbook/types/index.dart';
import 'package:deepbook/utils/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sui/models/dev_inspect_results.dart';
import 'package:sui/sui.dart';

final DEFAULT_FAUCET_URL = "https://faucet.testnet.sui.io";
final DEFAULT_FULLNODE_URL = "https://fullnode.testnet.sui.io";

final DEFAULT_TICK_SIZE = 1 * FLOAT_SCALING_FACTOR;
const DEFAULT_LOT_SIZE = 1;

class TestToolbox {
  SuiAccount account;
	SuiClient client;

	TestToolbox(this.account, this.client);

	String address() {
		return account.getAddress();
	}

	getActiveValidators() async {
		return (await client.getLatestSuiSystemState()).activeValidators;
	}
}

SuiClient getClient() {
	return SuiClient(DEFAULT_FULLNODE_URL);
}

Future<TestToolbox> setupSuiClient() async {
	// final keypair = Ed25519Keypair();
  final account = SuiAccount.fromMnemonics("result crisp session latin must fruit genuine question prevent start coconut brave speak student dismiss", SignatureScheme.Ed25519);
	// final address = keypair.getPublicKey().toSuiAddress();
  // FaucetClient(Constants.faucetDevAPI).requestSuiFromFaucetV0(account.getAddress());

	final client = getClient();
	return TestToolbox(account, client);
}

publishPackage(String packagePath, TestToolbox? toolbox) async {
	toolbox ??= await setupSuiClient();

  final modules = ["oRzrCwYAAAAKAQAMAgweAyonBFEKBVtfB7oBxQEI/wJgBt8DPAqbBAUMoAQ7ABABDAIGAhECEgITAAICAAEBBwEAAAIADAEAAQIDDAEAAQQEAgAFBQcAAAkAAQABDwUGAQACBwgJAQICCgwBAQADDQUBAQwEDgoLAAULAwQAAQQCBwMHBA0EDgIIAAcIBAACCwIBCAALAwEIAAEKAgEIBQEJAAELAQEJAAEIAAcJAAIKAgoCCgILAQEIBQcIBAILAwEJAAsCAQkAAQYIBAEFBAcLAwEJAAMFBwgEAQsCAQgAAQsDAQgADENvaW5NZXRhZGF0YQZPcHRpb24EVEVTVAtUcmVhc3VyeUNhcAlUeENvbnRleHQDVXJsBGNvaW4PY3JlYXRlX2N1cnJlbmN5C2R1bW15X2ZpZWxkBGluaXQRbWludF9hbmRfdHJhbnNmZXIVbmV3X3Vuc2FmZV9mcm9tX2J5dGVzBm9wdGlvbhNwdWJsaWNfc2hhcmVfb2JqZWN0BnNlbmRlcgRzb21lBHRlc3QIdHJhbnNmZXIKdHhfY29udGV4dAN1cmwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIKAgUEVEVTVAoCCglUZXN0IENvaW4KAhMSVGVzdCBjb2luIG1ldGFkYXRhCgIODWh0dHA6Ly9zdWkuaW8AAgEIAQAAAAACGAsAMQIHAAcBBwIHAxEGOAAKATgBDAIMAw0DBugDAAAAAAAACgEuEQULATgCCwI4AwsDOAQCAA=="];
  final dependencies = ["0x0000000000000000000000000000000000000000000000000000000000000001","0x0000000000000000000000000000000000000000000000000000000000000002"];
	final tx = TransactionBlock();
	final cap = tx.publish(
		modules,
		dependencies
	);

	// Transfer the upgrade capability to the sender so they can upgrade the package later if they want.
	tx.transferObjects([cap], tx.pureAddress(toolbox.address()));

	final publishTxn = await toolbox.client.signAndExecuteTransactionBlock(
		toolbox.account,
		tx,
		responseOptions: SuiTransactionBlockResponseOptions(
			showEffects: true,
			showObjectChanges: true,
    ),
	);
	expect(publishTxn.effects?.status.status, ExecutionStatusType.success);

	final packageId = publishTxn.objectChanges?.where(
		(a) => a["type"] == 'published',
	).toList()[0]["packageId"].toString().replaceAll(RegExp(r'^(0x)(0+)'), '0x');

	expect(packageId != null, true);

	debugPrint("Published package $packageId from address ${toolbox.address()}}");

	return { "packageId": packageId, "publishTxn": publishTxn };
}

Future<PoolSummary> setupPool(TestToolbox toolbox) async {
	final baseAsset = "0x3a678c27b2df65b466be4539629e2dba73e013e6454bc7b478285a3fd2c6211e::test::TEST";
	final quoteAsset = NORMALIZED_SUI_COIN_TYPE;

  return PoolSummary(
    "0x997c4bc9ccdb6a4e54578ec77f486c168b22cf171dd57fc34e3f26ac57711b9a",
    baseAsset,
    quoteAsset
  );

	// final packagePath = './data/test_coin';
	// final package = await publishPackage(packagePath, toolbox);
	// final baseAsset = "${package["packageId"]}::test::TEST";
	// final quoteAsset = NORMALIZED_SUI_COIN_TYPE;
	// final deepbook = DeepBookClient(client: toolbox.client);
	// final txb = deepbook.createPool(baseAsset, quoteAsset, DEFAULT_TICK_SIZE, DEFAULT_LOT_SIZE);
	// final resp = await executeTransactionBlock(toolbox, txb);
	// final event = resp.events.firstWhere((e) => e.type.contains('PoolCreated'));
  // return PoolSummary(
  //   event.parsedJson?["pool_id"] ?? "",
  //   baseAsset,
  //   quoteAsset
  // );
}

Future<String> setupDeepbookAccount(TestToolbox toolbox) async {
	final deepbook = DeepBookClient(client: toolbox.client);
	final txb = deepbook.createAccount(currentAddress: toolbox.address());
	final resp = await executeTransactionBlock(toolbox, txb);

	final accountCap = resp.objectChanges?.firstWhere(
		(a) => a["type"] == 'created',
	)["objectId"];
	return accountCap;
}

Future<SuiTransactionBlockResponse> executeTransactionBlock(
	TestToolbox toolbox,
	TransactionBlock txb,
) async {
	final resp = await toolbox.client.signAndExecuteTransactionBlock(
		toolbox.account,
		txb,
		responseOptions: SuiTransactionBlockResponseOptions(
			showEffects: true,
			showEvents: true,
			showObjectChanges: true,
    ),
	);
	expect(resp.effects?.status.status, ExecutionStatusType.success);
	return resp;
}

Future<DevInspectResults> devInspectTransactionBlock(
	TestToolbox toolbox,
	TransactionBlock txb,
) async {
	return await toolbox.client.devInspectTransactionBlock(
		toolbox.address(),
		txb
	);
}
