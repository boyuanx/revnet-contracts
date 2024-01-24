// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "lib/juice-contracts-v4/src/interfaces/IJBPermissioned.sol";
import {JBPermissionIds} from "lib/juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {JBBeforeRedeemRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBBeforePayRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforePayRecordedContext.sol";
import {JBRedeemHookSpecification} from "lib/juice-contracts-v4/src/structs/JBRedeemHookSpecification.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {JBPermissionsData} from "lib/juice-contracts-v4/src/structs/JBPermissionsData.sol";
import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBasicDeployer} from "./REVBasicDeployer.sol";
import {ITTUDeployer} from "lib/tokentable-v2-evm/contracts/interfaces/ITTUDeployer.sol";
import {ITokenTableUnlockerV2} from "lib/tokentable-v2-evm/contracts/interfaces/ITokenTableUnlockerV2.sol";
import {ITTFutureTokenV2} from "lib/tokentable-v2-evm/contracts/interfaces/ITTFutureTokenV2.sol";
import {ITTTrackerTokenV2} from "lib/tokentable-v2-evm/contracts/interfaces/ITTTrackerTokenV2.sol";
import {Preset, Actual} from "lib/tokentable-v2-evm/contracts/interfaces/TokenTableUnlockerV2DataModels.sol";
import {IJBToken} from "lib/juice-contracts-v4/src/interfaces/IJBToken.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

struct TokenTableUnlockerCreatePresetsData {
    bytes32[] presetIds;
    Preset[] presets;
    uint256 batchId;
    bytes extraData;
}

struct TokenTableUnlockerCreateActualsData {
    address[] recipients;
    Actual[] actuals;
    uint256[] recipientIds;
    uint256 batchId;
    bytes extraData;
}

struct TokenTableOptions {
    bool isUpgradeable;
    bool isTransferable;
    bool isCancelable;
    bool isHookable;
    bool isWithdrawable;
    TokenTableUnlockerCreatePresetsData presetData;
    TokenTableUnlockerCreateActualsData actualData;
}

/// @notice A contract that deploys a Revnet with TokenTable vesting for the boost operator.
contract REVTokenTableDeployer is REVBasicDeployer {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error REVTokenTableDeployer_InvalidTokenTableOptions();

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//
    ITTUDeployer public ttDeployer;
    mapping(uint256 revnetId => ITokenTableUnlockerV2) public ttUnlockerOf;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller that revnets are made from.
    /// @param ttDeployer_ The TokenTable Deployer singleton on the current chain.
    constructor(
        IJBController controller,
        ITTUDeployer ttDeployer_
    ) REVBasicDeployer(controller) {
        ttDeployer = ttDeployer_;
    }

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Deploy a basic revnet.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param metadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param ttOptions Data used to deploy and configure TokenTable.
    /// @return revnetId The ID of the newly created revnet.
    function deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        TokenTableOptions memory ttOptions
    ) public returns (uint256 revnetId) {
        // We only allow a single Preset and Actual to be passed in.
        // The Actual recipient must be the initial boost operator.
        if (
            ttOptions.presetData.presetIds.length != 1 ||
            ttOptions.actualData.recipients.length != 1 ||
            ttOptions.actualData.recipients[0] !=
            configuration.initialBoostOperator
        ) {
            revert REVTokenTableDeployer_InvalidTokenTableOptions();
        }
        return
            _deployRevnetWith({
                name: name,
                symbol: symbol,
                metadata: metadata,
                configuration: configuration,
                terminalConfigurations: terminalConfigurations,
                buybackHookConfiguration: buybackHookConfiguration,
                dataHook: buybackHookConfiguration.hook,
                extraHookMetadata: 0,
                ttOptions: ttOptions
            });
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Deploys a revnet with the specified hook information.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param metadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param dataHook The address of the data hook.
    /// @param extraHookMetadata Extra info to send to the hook.
    /// @param ttOptions Data used to deploy and configure TokenTable.
    /// @return revnetId The ID of the newly created revnet.
    function _deployRevnetWith(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        IJBBuybackHook dataHook,
        uint256 extraHookMetadata,
        TokenTableOptions memory ttOptions
    ) internal virtual returns (uint256 revnetId) {
        // Deploy a juicebox for the revnet.
        revnetId = CONTROLLER.launchProjectFor({
            owner: address(this),
            projectMetadata: metadata,
            rulesetConfigurations: _makeRulesetConfigurations(
                configuration,
                address(dataHook),
                extraHookMetadata
            ),
            terminalConfigurations: terminalConfigurations,
            memo: string.concat("$", symbol, " revnet deployed")
        });

        // Issue the network's ERC-20 token.
        IJBToken token = CONTROLLER.deployERC20For({
            projectId: revnetId,
            name: name,
            symbol: symbol
        });

        // Setup the buyback hook.
        _setupBuybackHookOf(revnetId, buybackHookConfiguration);

        // Set the boost allocations at the default ruleset of 0.
        CONTROLLER.setSplitGroupsOf({
            projectId: revnetId,
            rulesetId: 0,
            splitGroups: _makeBoostSplitGroupWith(
                configuration.initialBoostOperator
            )
        });

        // Deploy a TokenTable Suite. We only need the Unlocker instance here.
        (ITokenTableUnlockerV2 unlocker, , ) = ttDeployer.deployTTSuite(
            address(token),
            Strings.toString(revnetId),
            ttOptions.isUpgradeable,
            ttOptions.isTransferable,
            ttOptions.isCancelable,
            ttOptions.isHookable,
            ttOptions.isWithdrawable
        );
        // Configuring the Unlocker instance.
        unlocker.createPresets(
            ttOptions.presetData.presetIds,
            ttOptions.presetData.presets,
            ttOptions.presetData.batchId,
            ttOptions.presetData.extraData
        );
        unlocker.createActuals(
            ttOptions.actualData.recipients,
            ttOptions.actualData.actuals,
            ttOptions.actualData.recipientIds,
            ttOptions.actualData.batchId,
            ttOptions.actualData.extraData
        );
        // Save Unlocker instance to mapping.
        ttUnlockerOf[revnetId] = unlocker;
        // Transfer ownership of Unlocker from this contract to initial boost operator.
        Ownable(address(unlocker)).transferOwnership(
            configuration.initialBoostOperator
        );

        // Premint tokens to the boost operator if needed.
        // EDIT: Mint to TokenTable Unlocker instead.
        if (configuration.premintTokenAmount > 0) {
            // CONTROLLER.mintTokensOf({
            //     projectId: revnetId,
            //     tokenCount: configuration.premintTokenAmount,
            //     beneficiary: configuration.initialBoostOperator,
            //     memo: string.concat("$", symbol, " preminted"),
            //     useReservedRate: false
            // });
            CONTROLLER.mintTokensOf({
                projectId: revnetId,
                tokenCount: configuration.premintTokenAmount,
                beneficiary: address(unlocker),
                memo: string.concat("$", symbol, " preminted"),
                useReservedRate: false
            });
        }

        // Give the boost operator permission to change the boost recipients.
        IJBPermissioned(address(CONTROLLER)).PERMISSIONS().setPermissionsFor({
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: configuration.initialBoostOperator,
                projectId: revnetId,
                permissionIds: _BOOST_OPERATOR_PERMISSIONS_INDEXES
            })
        });
    }
}
