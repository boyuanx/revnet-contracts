// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBRulesetDataHook} from "lib/juice-contracts-v4/src/interfaces/IJBRulesetDataHook.sol";
import {JBPermissionIds} from "lib/juice-contracts-v4/src/libraries/JBPermissionIds.sol";
import {JBBeforeRedeemRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBBeforePayRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforePayRecordedContext.sol";
import {JBRedeemHookSpecification} from "lib/juice-contracts-v4/src/structs/JBRedeemHookSpecification.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBTerminalConfig} from "lib/juice-contracts-v4/src/structs/JBTerminalConfig.sol";
import {IJBBuybackHook} from "lib/juice-buyback/src/interfaces/IJBBuybackHook.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBasicDeployer} from "./REVBasicDeployer.sol";

/// @notice A contract that facilitates deploying a basic revnet that also calls other hooks when paid.
contract REVPayHookDeployer is REVBasicDeployer, IJBRulesetDataHook {
    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The data hook that returns the correct values for the buyback hook of each network.
    /// @custom:param revnetId The ID of the revnet to which the buyback contract applies.
    mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public buybackHookOf;

    //*********************************************************************//
    // -------------------- private stored properties -------------------- //
    //*********************************************************************//

    /// @notice The pay hooks to include during payments to networks.
    /// @custom:param revnetId The ID of the revnet to which the extensions apply.
    mapping(uint256 revnetId => JBPayHookSpecification[] payHooks) private _payHookSpecificationsOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The pay hooks to include during payments to networks.
    /// @param revnetId The ID of the revnet to which the extensions apply.
    /// @return payHookSpecifications The pay hooks.
    function payHookSpecificationsOf(uint256 revnetId) external view returns (JBPayHookSpecification[] memory) {
        return _payHookSpecificationsOf[revnetId];
    }

    /// @notice This function gets called when the revnet receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param context The Juicebox standard network payment context. See
    /// @return weight The weight that network tokens should get minted relative to. This is useful for optionally
    /// customizing how many tokens are issued per payment.
    /// @return hookSpecifications Amount to be sent to pay hooks instead of adding to local balance. Useful for
    /// auto-routing funds from a treasury as payment come in.

    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        virtual
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the hooks that the buyback hook data hook provides.
        JBPayHookSpecification[] memory buybackHookSpecifications;

        // // Set the values to be those returned by the buyback hook's data source.
        (weight, buybackHookSpecifications) = buybackHookOf[context.projectId].beforePayRecordedWith(context);

        // Check if a buyback hook is used.
        bool usesBuybackHook = buybackHookSpecifications.length != 0;

        // Cache any other pay hooks to use.
        JBPayHookSpecification[] memory storedPayHookSpecifications = _payHookSpecificationsOf[context.projectId];

        // Keep a reference to the number of pay hooks;
        uint256 numberOfStoredPayHookSpecifications = storedPayHookSpecifications.length;

        // Each hook specification must run, plus the buyback hook if provided.
        hookSpecifications =
            new JBPayHookSpecification[](numberOfStoredPayHookSpecifications + (usesBuybackHook ? 1 : 0));

        // Add the other expected pay hooks.
        for (uint256 i; i < numberOfStoredPayHookSpecifications; i++) {
            hookSpecifications[i] = storedPayHookSpecifications[i];
        }

        // Add the buyback hook as the last element.
        if (usesBuybackHook) hookSpecifications[numberOfStoredPayHookSpecifications] = buybackHookSpecifications[0];
    }

    /// @notice This function is never called, it needs to be included to adhere to the interface.
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata)
        external
        view
        virtual
        override
        returns (uint256, JBRedeemHookSpecification[] memory specifications)
    {
        return (0, specifications);
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(REVBasicDeployer, IERC165)
        returns (bool)
    {
        return interfaceId == type(IJBRulesetDataHook).interfaceId || super.supportsInterface(interfaceId);
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Required by the IJBRulesetDataHook interfaces.
    /// @param revnetId The ID of the revnet to check permissions for.
    /// @param addr The address to check if has permissions.
    /// @return flag The flag indicating if the address has permissions to mint on the revnet's behalf.
    function hasMintPermissionFor(uint256 revnetId, address addr) external view returns (bool) {
        return addr == address(buybackHookOf[revnetId]);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller that revnets are made from.
    constructor(IJBController controller) REVBasicDeployer(controller) {
        _BOOST_OPERATOR_PERMISSIONS_INDEXES.push(JBPermissionIds.MINT_TOKENS);
    }

    //*********************************************************************//
    // ---------------------- public transactions ------------------------ //
    //*********************************************************************//

    /// @notice Deploy a basic revnet that also calls other specified pay hooks.
    /// @param name The name of the ERC-20 token being create for the revnet.
    /// @param symbol The symbol of the ERC-20 token being created for the revnet.
    /// @param metadata The metadata containing revnet's info.
    /// @param configuration The data needed to deploy a basic revnet.
    /// @param terminalConfigurations The terminals that the network uses to accept payments through.
    /// @param buybackHookConfiguration Data used for setting up the buyback hook to use when determining the best price
    /// for new participants.
    /// @param payHookSpecifications Any hooks that should run when the revnet is paid.
    /// @param extraHookMetadata Extra metadata to attach to the cycle for the delegates to use.
    /// @return revnetId The ID of the newly created revnet.
    function deployPayHookRevnetWith(
        string memory name,
        string memory symbol,
        string memory metadata,
        REVConfig memory configuration,
        JBTerminalConfig[] memory terminalConfigurations,
        REVBuybackHookConfig memory buybackHookConfiguration,
        JBPayHookSpecification[] memory payHookSpecifications,
        uint16 extraHookMetadata
    )
        public
        returns (uint256 revnetId)
    {
        // Deploy the revnet
        revnetId = _deployRevnetWith({
            name: name,
            symbol: symbol,
            metadata: metadata,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            dataHook: IJBBuybackHook(address(this)),
            extraHookMetadata: extraHookMetadata
        });

        // Store the pay hooks.
        _storeHookSpecificationsOf(revnetId, payHookSpecifications);
    }

    //*********************************************************************//
    // --------------------- itnernal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Stores pay hooks for the provided revnet.
    /// @param revnetId The ID of the revnet to which the pay hooks apply.
    /// @param payHookSpecifications The pay hooks to store.
    function _storeHookSpecificationsOf(
        uint256 revnetId,
        JBPayHookSpecification[] memory payHookSpecifications
    )
        internal
    {
        // Keep a reference to the number of pay hooks are being stored.
        uint256 numberOfPayHookSpecifications = payHookSpecifications.length;

        // Store the pay hooks.
        for (uint256 i; i < numberOfPayHookSpecifications; i++) {
            // Store the value.
            _payHookSpecificationsOf[revnetId].push(payHookSpecifications[i]);
        }
    }
}
