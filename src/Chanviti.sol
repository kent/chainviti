// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Chainviti
 * @dev A multi-tenant invitation-based membership protocol with NFT minting.
 * Allows creation of apps, invitation flows, and membership management using ERC721 tokens.
 */
contract Chainviti is 
    Initializable, 
    ERC721Upgradeable, 
    ERC721EnumerableUpgradeable, 
    OwnableUpgradeable,
    UUPSUpgradeable 
{
    using Strings for uint256;

    // State variables
    mapping(bytes32 => mapping(address => bool)) public registered;        // Tracks registration status per app
    mapping(bytes32 => mapping(address => uint256)) public invitesLeft;    // Number of invites left per user, per app
    mapping(bytes32 => mapping(address => address)) public invitations;    // Pending invitations (invitee → inviter) per app
    mapping(uint256 => bytes32) public tokenAppId;                         // Associates each token ID with its app
    mapping(uint256 => address) public inviterOf;                          // Tracks the inviter who caused a given NFT to be minted
    mapping(bytes32 => address) public appOwner;                           // Primary app owner
    mapping(bytes32 => bool) public isTransferrable;                       // Indicates if NFTs for an app are transferrable
    mapping(bytes32 => string) public appBaseURI;                          // Base URI for NFT metadata, set per app
    mapping(bytes32 => uint256) public invitesPerNewUser;                  // Number of invites a new user gets upon joining
    mapping(uint256 => bool) public lockedTransfers;                       // Optional: Lock specific tokens from transfer
    
    // Optional multi-admin support
    mapping(bytes32 => mapping(address => bool)) public appAdmins;         // Additional admins per app
    
    // Counter for token IDs
    uint256 private _tokenIdCounter;
    
    // Events
    event AppCreated(bytes32 indexed appId, address indexed owner);
    event InviteSent(bytes32 indexed appId, address indexed inviter, address indexed invitee);
    event InviteAccepted(bytes32 indexed appId, address indexed user, address indexed inviter, uint256 tokenId);
    event TransferrableSet(bytes32 indexed appId, bool isTransferrable);
    event AppOwnershipTransferred(bytes32 indexed appId, address indexed newOwner);
    event AdminAdded(bytes32 indexed appId, address indexed admin);
    event AdminRemoved(bytes32 indexed appId, address indexed admin);
    event TokenLocked(uint256 indexed tokenId, bool locked);
    event InvitesGranted(bytes32 indexed appId, address indexed user, uint256 amount);
    event BaseURISet(bytes32 indexed appId, string baseURI);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the contract with default values.
     */
    function initialize() initializer public {
        __ERC721_init("Chainviti", "CVT");
        __ERC721Enumerable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }
    
    /**
     * @dev Creates a new app with the given ID and settings.
     * @param appId Unique identifier for the app
     * @param initialInvites Number of initial invites the creator gets
     * @param _invitesPerNewUser Number of invites each new user gets
     */
    function createApp(bytes32 appId, uint256 initialInvites, uint256 _invitesPerNewUser) external {
        require(appOwner[appId] == address(0), "App already exists");
        require(initialInvites <= 1000, "Too many initial invites"); // Sanity check
        require(_invitesPerNewUser <= 100, "Too many invites per user"); // Sanity check
        
        appOwner[appId] = msg.sender;
        registered[appId][msg.sender] = true;
        invitesLeft[appId][msg.sender] = initialInvites;
        invitesPerNewUser[appId] = _invitesPerNewUser;
        isTransferrable[appId] = true; // Default to transferrable
        appAdmins[appId][msg.sender] = true; // Owner is also an admin
        
        emit AppCreated(appId, msg.sender);
    }
    
    /**
     * @dev Sends an invitation to a new user for a specific app.
     * @param appId The app ID
     * @param newUserAddress Address of the user to invite
     */
    function invite(bytes32 appId, address newUserAddress) external {
        require(registered[appId][msg.sender], "You are not registered");
        require(invitesLeft[appId][msg.sender] > 0, "No invites left");
        require(!registered[appId][newUserAddress], "Already registered");
        require(invitations[appId][newUserAddress] == address(0), "User already invited");
        require(newUserAddress != address(0), "Invalid address");
        
        invitations[appId][newUserAddress] = msg.sender;
        invitesLeft[appId][msg.sender] -= 1;
        
        emit InviteSent(appId, msg.sender, newUserAddress);
    }
    
    /**
     * @dev Accepts an invitation to an app, mints an NFT, and grants initial invites.
     * @param appId The app ID to join
     */
    function acceptInvite(bytes32 appId) external {
        address inviter = invitations[appId][msg.sender];
        require(inviter != address(0), "No pending invite");
        require(!registered[appId][msg.sender], "Already registered");
        
        registered[appId][msg.sender] = true;
        
        uint256 newTokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(msg.sender, newTokenId);
        tokenAppId[newTokenId] = appId;
        inviterOf[newTokenId] = inviter;
        invitesLeft[appId][msg.sender] = invitesPerNewUser[appId];
        
        // Cleanup
        delete invitations[appId][msg.sender];
        
        emit InviteAccepted(appId, msg.sender, inviter, newTokenId);
    }
    
    /**
     * @dev Overrides transferFrom to respect app transferrability settings.
     */
    function transferFrom(
        address from, 
        address to, 
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721) {
        bytes32 appId = tokenAppId[tokenId];
        require(isTransferrable[appId], "App not transferrable");
        require(!lockedTransfers[tokenId], "Token transfer locked");
        super.transferFrom(from, to, tokenId);
    }
    
    /**
     * @dev Overrides safeTransferFrom to respect app transferrability settings.
     */
    function safeTransferFrom(
        address from, 
        address to, 
        uint256 tokenId, 
        bytes memory data
    ) public override(ERC721Upgradeable, IERC721) {
        bytes32 appId = tokenAppId[tokenId];
        require(isTransferrable[appId], "App not transferrable");
        require(!lockedTransfers[tokenId], "Token transfer locked");
        super.safeTransferFrom(from, to, tokenId, data);
    }
    
    /**
     * @dev Sets whether NFTs for an app can be transferred.
     * @param appId The app ID
     * @param _isTransferrable Whether tokens can be transferred
     */
    function setTransferrable(bytes32 appId, bool _isTransferrable) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        isTransferrable[appId] = _isTransferrable;
        emit TransferrableSet(appId, _isTransferrable);
    }
    
    /**
     * @dev Sets how many invites new users get when joining an app.
     * @param appId The app ID
     * @param _invites Number of invites for new users
     */
    function setInvitesPerNewUser(bytes32 appId, uint256 _invites) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        require(_invites <= 100, "Too many invites per user"); // Sanity check
        invitesPerNewUser[appId] = _invites;
    }
    
    /**
     * @dev Grants additional invites to a user.
     * @param appId The app ID
     * @param user User to receive invites
     * @param amount Number of invites to grant
     */
    function grantInvites(bytes32 appId, address user, uint256 amount) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        require(registered[appId][user], "User not registered");
        require(amount <= 1000, "Too many invites"); // Sanity check
        
        invitesLeft[appId][user] += amount;
        emit InvitesGranted(appId, user, amount);
    }
    
    /**
     * @dev Sets the base URI for token metadata for an app.
     * @param appId The app ID
     * @param baseURI The base URI for metadata
     */
    function setAppBaseURI(bytes32 appId, string memory baseURI) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        appBaseURI[appId] = baseURI;
        emit BaseURISet(appId, baseURI);
    }
    
    /**
     * @dev Returns metadata URI for a specific token.
     * @param tokenId The token ID
     * @return Token URI string
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Check if token exists by trying to get its owner
        try this.ownerOf(tokenId) returns (address) {
            // Token exists
        } catch {
            revert("Token does not exist");
        }
        
        bytes32 appId = tokenAppId[tokenId];
        string memory base = appBaseURI[appId];
        
        if (bytes(base).length > 0) {
            return string(abi.encodePacked(base, tokenId.toString()));
        }
        
        // Default fallback
        return string(abi.encodePacked("https://chainviti.xyz/metadata/", tokenId.toString()));
    }
    
    /**
     * @dev Checks if a user has access to an app.
     * @param appId The app ID
     * @param user User address to check
     * @return True if user has access
     */
    function hasAccess(bytes32 appId, address user) public view returns (bool) {
        // Direct registration check for efficiency
        if (registered[appId][user]) {
            return true;
        }
        
        // Token-based check (less efficient for users with many tokens)
        uint256 balance = balanceOf(user);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (tokenAppId[tokenId] == appId) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Transfers ownership of an app to a new owner.
     * @param appId The app ID
     * @param newOwner New owner address
     */
    function transferAppOwnership(bytes32 appId, address newOwner) external {
        require(msg.sender == appOwner[appId], "Not app owner");
        require(newOwner != address(0), "Invalid new owner");
        
        appOwner[appId] = newOwner;
        
        // Make new owner an admin if not already
        if (!appAdmins[appId][newOwner]) {
            appAdmins[appId][newOwner] = true;
        }
        
        emit AppOwnershipTransferred(appId, newOwner);
    }
    
    /**
     * @dev Adds an admin to an app.
     * @param appId The app ID
     * @param admin Admin address to add
     */
    function addAdmin(bytes32 appId, address admin) external {
        require(msg.sender == appOwner[appId], "Not app owner");
        require(admin != address(0), "Invalid admin address");
        
        appAdmins[appId][admin] = true;
        emit AdminAdded(appId, admin);
    }
    
    /**
     * @dev Removes an admin from an app.
     * @param appId The app ID
     * @param admin Admin address to remove
     */
    function removeAdmin(bytes32 appId, address admin) external {
        require(msg.sender == appOwner[appId], "Not app owner");
        require(admin != appOwner[appId], "Cannot remove owner as admin");
        
        appAdmins[appId][admin] = false;
        emit AdminRemoved(appId, admin);
    }
    
    /**
     * @dev Locks or unlocks a specific token from being transferred.
     * @param tokenId Token to lock/unlock
     * @param locked Whether to lock the token
     */
    function setTokenLocked(uint256 tokenId, bool locked) external {
        // Check if token exists by trying to get its owner
        try this.ownerOf(tokenId) returns (address) {
            // Token exists
        } catch {
            revert("Token does not exist");
        }
        
        bytes32 appId = tokenAppId[tokenId];
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        
        lockedTransfers[tokenId] = locked;
        emit TokenLocked(tokenId, locked);
    }
    
    /**
     * @dev Batch invite multiple users at once (gas optimization).
     * @param appId The app ID
     * @param newUserAddresses Array of addresses to invite
     */
    function batchInvite(bytes32 appId, address[] calldata newUserAddresses) external {
        require(registered[appId][msg.sender], "You are not registered");
        require(invitesLeft[appId][msg.sender] >= newUserAddresses.length, "Not enough invites");
        
        for (uint256 i = 0; i < newUserAddresses.length; i++) {
            address newUser = newUserAddresses[i];
            
            require(!registered[appId][newUser], "User already registered");
            require(invitations[appId][newUser] == address(0), "User already invited");
            require(newUser != address(0), "Invalid address");
            
            invitations[appId][newUser] = msg.sender;
            emit InviteSent(appId, msg.sender, newUser);
        }
        
        invitesLeft[appId][msg.sender] -= newUserAddresses.length;
    }
    
    /**
     * @dev Checks if a user is an admin for an app.
     * @param appId The app ID
     * @param user User to check
     * @return True if user is an admin
     */
    function isAppAdmin(bytes32 appId, address user) external view returns (bool) {
        return _isAppAdmin(appId, user);
    }
    
    /**
     * @dev Internal function to check if a user is an admin.
     * @param appId The app ID
     * @param user User to check
     * @return True if user is an admin
     */
    function _isAppAdmin(bytes32 appId, address user) internal view returns (bool) {
        return user == appOwner[appId] || appAdmins[appId][user];
    }
    
    /**
     * @dev Implement required function to resolve inheritance conflicts
     */
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        address from = super._update(to, tokenId, auth);
        
        // Update registration status if this is a transfer (not a mint or burn)
        if (from != address(0) && to != address(0)) {
            bytes32 appId = tokenAppId[tokenId];
            registered[appId][to] = true;
        }
        
        return from;
    }
    
    /**
     * @dev Implement required function to resolve inheritance conflicts
     */
    function _increaseBalance(address account, uint128 amount) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, amount);
    }
    
    /**
     * @dev Required function for UUPS upgradeable contracts.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Required override for ERC721Enumerable compatibility.
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}