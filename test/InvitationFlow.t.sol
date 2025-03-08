// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Chainviti.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract InvitationFlowTest is Test {
    Chainviti public implementation;
    Chainviti public chainviti;
    
    address public userA;
    address public userB;
    address public userC;
    address public userD;
    
    bytes32 public appId;
    uint256 public initialInvites = 5; // Initial invites for app creator
    uint256 public invitesPerNewUser = 2; // Invites granted to each new user
    
    uint256 public userAInvitationTokenId;
    uint256 public userBMembershipTokenId;
    uint256 public userBInvitationTokenId;
    uint256 public userCInvitationTokenId;
    uint256 public userDMembershipTokenId;
    
    function setUp() public {
        // Setup test accounts with labels for easier debugging
        userA = address(0x1);
        userB = address(0x2);
        userC = address(0x3);
        userD = address(0x4);
        
        vm.label(userA, "UserA");
        vm.label(userB, "UserB");
        vm.label(userC, "UserC");
        vm.label(userD, "UserD");
        
        // Deploy the implementation contract
        implementation = new Chainviti();
        
        // Deploy the proxy pointing to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(Chainviti.initialize.selector)
        );
        
        // Cast the proxy address to the Chainviti interface
        chainviti = Chainviti(address(proxy));
        
        // Generate a unique app ID
        appId = keccak256(abi.encodePacked("TestApp", block.timestamp));
    }
    
    function testCompleteInvitationFlow() public {
        // Step 1: User A creates an app and invites user B
        vm.startPrank(userA);
        
        // Create the app
        chainviti.createApp(appId, initialInvites, invitesPerNewUser);
        
        // Verify app creation
        assertEq(chainviti.getAppOwner(appId), userA);
        assertEq(chainviti.isRegistered(appId, userA), true);
        assertEq(chainviti.getInvitesLeft(appId, userA), initialInvites);
        
        // User A invites User B
        chainviti.invite(appId, userB);
        
        // Verify User A's invites decreased
        assertEq(chainviti.getInvitesLeft(appId, userA), initialInvites - 1);
        
        vm.stopPrank();
        
        // Step 2: Verify User B received the invitation NFT
        uint256[] memory userBTokens = getOwnedTokenIds(userB);
        assertEq(userBTokens.length, 1);
        userAInvitationTokenId = userBTokens[0];
        
        // Verify the token is an invitation token
        assertEq(uint8(chainviti.getTokenType(userAInvitationTokenId)), uint8(Chainviti.TokenType.INVITATION));
        assertEq(chainviti.getTokenAppId(userAInvitationTokenId), appId);
        assertEq(chainviti.getInviterOf(userAInvitationTokenId), userA);
        
        // Step 3: User B accepts the invitation
        vm.startPrank(userB);
        
        // B is not registered yet
        assertEq(chainviti.isRegistered(appId, userB), false);
        
        // B accepts the invite
        chainviti.acceptInvite(userAInvitationTokenId);
        
        // Verify B is now registered and received invites
        assertEq(chainviti.isRegistered(appId, userB), true);
        assertEq(chainviti.getInvitesLeft(appId, userB), invitesPerNewUser);
        
        // Get B's membership token ID
        uint256[] memory userBMembershipTokens = getOwnedTokenIds(userB);
        assertEq(userBMembershipTokens.length, 1);
        userBMembershipTokenId = userBMembershipTokens[0];
        
        // Verify it's a membership token
        assertEq(uint8(chainviti.getTokenType(userBMembershipTokenId)), uint8(Chainviti.TokenType.MEMBERSHIP));
        
        // Step 4: User B invites User C
        chainviti.invite(appId, userC);
        
        // Verify B's invites decreased
        assertEq(chainviti.getInvitesLeft(appId, userB), invitesPerNewUser - 1);
        
        vm.stopPrank();
        
        // Step 5: Verify User C received the invitation NFT
        uint256[] memory userCTokens = getOwnedTokenIds(userC);
        assertEq(userCTokens.length, 1);
        userBInvitationTokenId = userCTokens[0];
        
        // Verify the token is an invitation token
        assertEq(uint8(chainviti.getTokenType(userBInvitationTokenId)), uint8(Chainviti.TokenType.INVITATION));
        assertEq(chainviti.getTokenAppId(userBInvitationTokenId), appId);
        assertEq(chainviti.getInviterOf(userBInvitationTokenId), userB);
        
        // Step 6: User C transfers invitation to User D
        vm.startPrank(userC);
        
        // Verify C is not registered (just has an invite)
        assertEq(chainviti.isRegistered(appId, userC), false);
        
        // C transfers invitation to D
        chainviti.transferFrom(userC, userD, userBInvitationTokenId);
        
        vm.stopPrank();
        
        // Verify User C no longer has the token
        userCTokens = getOwnedTokenIds(userC);
        assertEq(userCTokens.length, 0);
        
        // Verify User D now has the token
        uint256[] memory userDTokens = getOwnedTokenIds(userD);
        assertEq(userDTokens.length, 1);
        userCInvitationTokenId = userDTokens[0];
        
        // The original inviter should still be User B
        assertEq(chainviti.getInviterOf(userCInvitationTokenId), userB);
        
        // Step 7: User D accepts the invitation
        vm.startPrank(userD);
        
        // D is not registered yet
        assertEq(chainviti.isRegistered(appId, userD), false);
        
        // D accepts the invite
        chainviti.acceptInvite(userCInvitationTokenId);
        
        // Verify D is now registered and received invites
        assertEq(chainviti.isRegistered(appId, userD), true);
        assertEq(chainviti.getInvitesLeft(appId, userD), invitesPerNewUser);
        
        // Get D's membership token ID
        uint256[] memory userDMembershipTokens = getOwnedTokenIds(userD);
        assertEq(userDMembershipTokens.length, 1);
        userDMembershipTokenId = userDMembershipTokens[0];
        
        // Verify it's a membership token
        assertEq(uint8(chainviti.getTokenType(userDMembershipTokenId)), uint8(Chainviti.TokenType.MEMBERSHIP));
        
        vm.stopPrank();
        
        // Final verification of invite counts
        assertEq(chainviti.getInvitesLeft(appId, userA), initialInvites - 1);
        assertEq(chainviti.getInvitesLeft(appId, userB), invitesPerNewUser - 1);
        assertEq(chainviti.getInvitesLeft(appId, userC), 0); // C never registered
        assertEq(chainviti.getInvitesLeft(appId, userD), invitesPerNewUser);
        
        // Verify User C is not registered (they just passed the invite)
        assertEq(chainviti.isRegistered(appId, userC), false);
        
        // Verify registered status
        assertEq(chainviti.isRegistered(appId, userA), true);
        assertEq(chainviti.isRegistered(appId, userB), true);
        assertEq(chainviti.isRegistered(appId, userD), true);
        
        // Verify app membership via the hasAccess function
        assertTrue(chainviti.hasAccess(appId, userA));
        assertTrue(chainviti.hasAccess(appId, userB));
        assertFalse(chainviti.hasAccess(appId, userC));
        assertTrue(chainviti.hasAccess(appId, userD));
    }
    
    // Helper function to get all token IDs owned by an address
    function getOwnedTokenIds(address owner) internal view returns (uint256[] memory) {
        uint256 balance = chainviti.balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = chainviti.tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }
    
    // Test for edge cases
    function testFailAcceptNonExistentInvitation() public {
        vm.startPrank(userA);
        chainviti.createApp(appId, initialInvites, invitesPerNewUser);
        vm.stopPrank();
        
        // Try to accept an invitation that doesn't exist
        vm.startPrank(userB);
        chainviti.acceptInvite(999); // Should fail
        vm.stopPrank();
    }
    
    function testFailAcceptOthersInvitation() public {
        vm.startPrank(userA);
        chainviti.createApp(appId, initialInvites, invitesPerNewUser);
        chainviti.invite(appId, userB);
        vm.stopPrank();
        
        uint256[] memory userBTokens = getOwnedTokenIds(userB);
        uint256 invitationTokenId = userBTokens[0];
        
        // User C tries to accept B's invitation
        vm.startPrank(userC);
        chainviti.acceptInvite(invitationTokenId); // Should fail
        vm.stopPrank();
    }
    
    function testFailInviteWithoutInvitesLeft() public {
        // A creates app with 1 invite
        vm.startPrank(userA);
        chainviti.createApp(appId, 1, invitesPerNewUser);
        
        // Use the one invite
        chainviti.invite(appId, userB);
        
        // Try to invite again without invites left
        chainviti.invite(appId, userC); // Should fail
        vm.stopPrank();
    }
} 