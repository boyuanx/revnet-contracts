// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { CroptopPublisher, AllowedPost } from "@croptop/publisher/src/CroptopPublisher.sol";
import { JB721Operations } from "@jbx-protocol/juice-721-delegate/contracts/libraries/JB721Operations.sol";
import { IJBTiered721DelegateDeployer } from
    "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateDeployer.sol";
import { JBDeployTiered721DelegateData } from
    "@jbx-protocol/juice-721-delegate/contracts/structs/JBDeployTiered721DelegateData.sol";
import { IJBController3_1 } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import { IJBDirectory } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import { IJBPaymentTerminal } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import { IJBOperatable } from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatable.sol";
import { IJBPayoutRedemptionPaymentTerminal3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal3_1_1.sol";
import { JBOperatorData } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import { JBPayDelegateAllocation3_1_1 } from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import { JBProjectMetadata } from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import { IJBGenericBuybackDelegate } from
    "@jbx-protocol/juice-buyback-delegate/contracts/interfaces/IJBGenericBuybackDelegate.sol";
import { REVTiered721RevnetDeployer } from "./REVTiered721RevnetDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also can mint tiered 721s via a croptop proxy.
contract REVCroptopDeployer is REVTiered721RevnetDeployer {
    /// @notice The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    CroptopPublisher public PUBLISHER;

    /// @notice The permissions that the croptop publisher should be granted. This is set once in the constructor to
    /// contain only the ADJUST_TIERS operation.
    uint256[] internal _CROPTOP_PERMISSIONS_INDEXES;

    /// @param controller The controller that revnets are made from.
    /// @param hookDeployer The 721 tiers hook deployer.
    /// @param publisher The croptop publisher that facilitates the permissioned publishing of 721 posts to a revnet.
    constructor(
        IJBController controller, 
        IJB721TiersHookDeployer hookDeployer,
        CroptopPublisher publisher
    )
        Tiered721RevnetDeployer(controller, hookDeployer )
    {
        PUBLISHER = publisher;
        _CROPTOP_PERMISSIONS_INDEXES.push(JB721Operations.ADJUST_TIERS);
    }

    /// @notice Deploy a revnet that supports 721 sales.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param metadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param hookConfiguration Data used for setting up the 721 tiers.
    /// @param otherPayHooksSpecifications Any hooks that should run when the revnet is paid alongside the 721 hook.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @param allowedPosts The type of posts that the network should allow.
    /// @return revnetId The ID of the newly created revnet.
    function deployCroptopRevnetFor(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        JBDeploy721TiersHookConfig memory hookConfiguration,
        JBPayHookSpecification[] memory otherPayHooksSpecifications,
        uint16 extraHookMetadata
        AllowedPost[] memory allowedPosts
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet with tiered 721 hooks.
        revnetId = super.deployTiered721RevnetFor({
            name: name,
            symbol: symbol,
            metadata: metadata,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfigurations: buybackHookConfigurations,
            hookConfiguration: hookConfiguration,
            otherPayHooksSpecifications: otherPayHooksSpecifications,
            extraHookMetadata: extraHookMetadata
        });

        // Configure allowed posts.
        if (allowedPosts.length != 0) publisher.configurePostingCriteriaFor(revnetId, allowedPosts);

        // Give the croptop publisher permission to post on this contract's behalf.
        IJBPermissioned(address(controller)).PERMISSIONS().setPermissionsFor(
            account: address(this),
            permissionsData: JBPermissionsData({
                operator: address(publisher),
                projectId: revnetId,
                permissionIds: _CROPTOP_PERMISSIONS_INDEXES
            })
        );
    }
}