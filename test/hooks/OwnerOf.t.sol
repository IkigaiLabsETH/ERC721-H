// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
// Forge Imports
import {DSTest} from "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";
// interface imports
import {ICre8ors} from "../../src/interfaces/ICre8ors.sol";
import {IERC721Drop} from "../../src/interfaces/IERC721Drop.sol";
import {IFriendsAndFamilyMinter} from "../../src/interfaces/IFriendsAndFamilyMinter.sol";
import {ILockup} from "../../src/interfaces/ILockup.sol";
import {IMinterUtilities} from "../../src/interfaces/IMinterUtilities.sol";
import {IERC721ACH} from "ERC721H/interfaces/IERC721ACH.sol";
// contract imports
import {Cre8ors} from "../../src/Cre8ors.sol";
import {Cre8orTestBase} from "../utils/Cre8orTestBase.sol";
import {DummyMetadataRenderer} from "../utils/DummyMetadataRenderer.sol";
import {FriendsAndFamilyMinter} from "../../src/minter/FriendsAndFamilyMinter.sol";
import {Lockup} from "../../src/utils/Lockup.sol";
import {MinterUtilities} from "../../src/utils/MinterUtilities.sol";
import {Cre8ing} from "../../src/Cre8ing.sol";
import {Subscription} from "../../src/subscription/Subscription.sol";
import {OwnerOfHook} from "../../src/hooks/OwnerOf.sol";
import {TransferHook} from "../../src/hooks/Transfers.sol";

contract OwnerOfHookTest is DSTest, Cre8orTestBase {
    FriendsAndFamilyMinter public minter;
    MinterUtilities public minterUtility;
    Cre8ing public cre8ingBase;
    address public familyMinter = address(0x1234567);

    Lockup lockup = new Lockup();

    uint64 public constant ONE_YEAR_DURATION = 365 days;

    OwnerOfHook public ownerOfHook;

    Subscription public subscription;

    function setUp() public {
        Cre8orTestBase.cre8orSetup();
        minterUtility = new MinterUtilities(
            address(cre8orsNFTBase),
            50000000000000000,
            100000000000000000,
            150000000000000000
        );
        minter = new FriendsAndFamilyMinter(
            address(cre8orsNFTBase),
            address(minterUtility)
        );

        subscription = _setupSubscription();
        cre8ingBase = new Cre8ing();

        transferHook = _setupTransferHook();
        ownerOfHook = _setupOwnerOfHook();

        _setupErc6551();
    }

    function testSuccessfulOwnerOfWithoutLockup(
        address _friendOrFamily
    ) public {
        vm.assume(_friendOrFamily != address(0));

        // Setup Minter
        _setupMinter();

        // Apply Discount
        _addDiscount(_friendOrFamily);
        // Mint
        uint256 tokenId = minter.mint(_friendOrFamily);

        // Asserts
        assertTrue(!minter.hasDiscount(_friendOrFamily));
        assertEq(tokenId, 1);
        assertEq(cre8orsNFTBase.ownerOf(tokenId), _friendOrFamily);
        assertEq(
            cre8orsNFTBase.mintedPerAddress(_friendOrFamily).totalMints,
            1
        );
        assertTrue(subscription.isSubscriptionValid(tokenId));

        // 1 year passed
        vm.warp(block.timestamp + ONE_YEAR_DURATION);

        // ownerOf should return address(0)
        assertEq(cre8orsNFTBase.ownerOf(tokenId), address(0));
        assertTrue(!subscription.isSubscriptionValid(tokenId));
    }

    function testSuccessfulOwnerOfWithLockup(address _friendOrFamily) public {
        vm.assume(_friendOrFamily != address(0));

        // Setup Minter
        _setupMinter();

        // Apply Discount
        _addDiscount(_friendOrFamily);

        // Mint
        uint256 tokenId = minter.mint(_friendOrFamily);

        // Asserts
        assertTrue(!minter.hasDiscount(_friendOrFamily));
        assertEq(tokenId, 1);
        assertEq(cre8orsNFTBase.ownerOf(tokenId), _friendOrFamily);
        assertEq(
            cre8orsNFTBase.mintedPerAddress(_friendOrFamily).totalMints,
            1
        );
        assertTrue(subscription.isSubscriptionValid(tokenId));

        // 1 year passed
        vm.warp(block.timestamp + ONE_YEAR_DURATION);

        // ownerOf should return address(0)
        assertEq(cre8orsNFTBase.ownerOf(tokenId), address(0));
        assertTrue(!subscription.isSubscriptionValid(tokenId));
    }

    /// HELPER FUNCTIONS ///

    function _addDiscount(address _buyer) internal {
        assertTrue(!minter.hasDiscount(_buyer));
        vm.prank(DEFAULT_OWNER_ADDRESS);
        minter.addDiscount(_buyer);
        assertTrue(minter.hasDiscount(_buyer));
    }

    function _setMinterRole(address _assignee) internal {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        cre8orsNFTBase.grantRole(
            cre8orsNFTBase.MINTER_ROLE(),
            address(_assignee)
        );
        vm.stopPrank();
    }

    /// SETUP CONTRACT FUNCTIONS ///

    function _setupMinter() internal {
        bytes32 role = cre8orsNFTBase.MINTER_ROLE();
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        cre8orsNFTBase.grantRole(role, address(minter));
        cre8orsNFTBase.grantRole(
            cre8orsNFTBase.MINTER_ROLE(),
            address(cre8ingBase)
        );
        cre8ingBase.setCre8ingOpen(address(cre8orsNFTBase), true);

        cre8ingBase.setLockup(address(cre8orsNFTBase), lockup);
        assertTrue(
            cre8orsNFTBase.hasRole(
                cre8orsNFTBase.MINTER_ROLE(),
                address(minter)
            )
        );
        vm.stopPrank();
    }

    function _setupOwnerOfHook() internal returns (OwnerOfHook) {
        ownerOfHook = new OwnerOfHook();
        _setMinterRole(address(ownerOfHook));

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        // set hook
        cre8orsNFTBase.setHook(
            IERC721ACH.HookType.OwnerOf,
            address(ownerOfHook)
        );
        // set subscription
        ownerOfHook.setSubscription(
            address(cre8orsNFTBase),
            address(subscription)
        );
        vm.stopPrank();

        return ownerOfHook;
    }

    function _setupTransferHook() internal returns (TransferHook) {
        _setupErc6551();
        _setMinterRole(address(transferHook));

        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        // set hook
        cre8orsNFTBase.setHook(
            IERC721ACH.HookType.AfterTokenTransfers,
            address(transferHook)
        );
        cre8orsNFTBase.setHook(
            IERC721ACH.HookType.BeforeTokenTransfers,
            address(transferHook)
        );
        // set subscription
        transferHook.setSubscription(
            address(cre8orsNFTBase),
            address(subscription)
        );
        // set cre8ing
        transferHook.setCre8ing(address(cre8ingBase));

        vm.stopPrank();

        return transferHook;
    }

    function _setupSubscription() internal returns (Subscription) {
        subscription = new Subscription({
            cre8orsNFT_: address(cre8orsNFTBase),
            minRenewalDuration_: 1 days,
            pricePerSecond_: 38580246913 // Roughly calculates to 0.1 ether per 30 days
        });

        return subscription;
    }
}
