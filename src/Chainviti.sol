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
 * Invitations themselves are NFTs that can be transferred between users.
 */
contract Chainviti is 
    Initializable, 
    ERC721Upgradeable, 
    ERC721EnumerableUpgradeable, 
    OwnableUpgradeable,
    UUPSUpgradeable 
{
    using Strings for uint256;

    // Token type enum
    enum TokenType { NONE, MEMBERSHIP, INVITATION }
    
    // Token data struct to group token-related attributes
    struct TokenData {
        bytes32 appId;          // App this token belongs to
        TokenType tokenType;    // Membership or invitation
        address inviter;        // Who invited this token holder
        bool locked;            // Whether token is locked from transfers
    }
    
    // App data struct to group app-related settings and state
    struct AppData {
        address owner;                          // Primary app owner
        bool isTransferrable;                   // Whether NFTs can be transferred
        string baseURI;                         // Base URI for NFT metadata
        uint256 invitesPerNewUser;              // Invites per new user
        mapping(address => bool) admins;        // Additional admins
        mapping(address => bool) registered;    // Registered users
        mapping(address => uint256) invitesLeft;// Invites left per user
    }
    
    // State variables
    mapping(uint256 => TokenData) private _tokenData;           // Token data per token ID
    mapping(bytes32 => AppData) private _appData;               // App data per app ID
    
    // Counter for token IDs
    uint256 private _tokenIdCounter;
    
    // Events
    event AppCreated(bytes32 indexed appId, address indexed owner);
    event InviteSent(bytes32 indexed appId, address indexed inviter, address indexed invitee, uint256 invitationTokenId);
    event InviteAccepted(bytes32 indexed appId, address indexed user, address indexed inviter, uint256 membershipTokenId);
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
        require(_appData[appId].owner == address(0), "App already exists");
        require(initialInvites <= 1000, "Too many initial invites"); // Sanity check
        require(_invitesPerNewUser <= 100, "Too many invites per user"); // Sanity check
        
        // Initialize app data
        _appData[appId].owner = msg.sender;
        _appData[appId].isTransferrable = true; // Default to transferrable
        _appData[appId].invitesPerNewUser = _invitesPerNewUser;
        
        // Register creator and give invites
        _appData[appId].registered[msg.sender] = true;
        _appData[appId].invitesLeft[msg.sender] = initialInvites;
        _appData[appId].admins[msg.sender] = true; // Owner is also an admin
        
        // Mint a membership token for the app creator
        uint256 newTokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(msg.sender, newTokenId);
        
        // Set token data
        _tokenData[newTokenId].appId = appId;
        _tokenData[newTokenId].tokenType = TokenType.MEMBERSHIP;
        
        emit AppCreated(appId, msg.sender);
    }
    
    /**
     * @dev Sends an invitation to a new user for a specific app.
     * Mints an invitation NFT that can be transferred to other users.
     * @param appId The app ID
     * @param recipient Address to receive the invitation NFT
     */
    function invite(bytes32 appId, address recipient) external {
        require(_appData[appId].registered[msg.sender], "You are not registered");
        require(_appData[appId].invitesLeft[msg.sender] > 0, "No invites left");
        require(recipient != address(0), "Invalid address");
        
        // Mint an invitation token to the recipient
        uint256 invitationTokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(recipient, invitationTokenId);
        
        // Set token data
        _tokenData[invitationTokenId].appId = appId;
        _tokenData[invitationTokenId].tokenType = TokenType.INVITATION;
        _tokenData[invitationTokenId].inviter = msg.sender;
        
        // Decrement invites left
        _appData[appId].invitesLeft[msg.sender] -= 1;
        
        emit InviteSent(appId, msg.sender, recipient, invitationTokenId);
    }
    
    /**
     * @dev Accepts an invitation to an app, burns the invitation NFT, and mints a membership NFT.
     * @param invitationTokenId The token ID of the invitation to accept
     */
    function acceptInvite(uint256 invitationTokenId) external {
        // Check that sender owns the invitation token
        require(ownerOf(invitationTokenId) == msg.sender, "Not invitation owner");
        require(_tokenData[invitationTokenId].tokenType == TokenType.INVITATION, "Not an invitation token");
        
        bytes32 appId = _tokenData[invitationTokenId].appId;
        address inviter = _tokenData[invitationTokenId].inviter;
        
        require(!_appData[appId].registered[msg.sender], "Already registered");
        
        // Register the user
        _appData[appId].registered[msg.sender] = true;
        
        // Mint a new membership token
        uint256 membershipTokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        // Burn the invitation token
        _burn(invitationTokenId);
        
        // Mint the membership token
        _safeMint(msg.sender, membershipTokenId);
        
        // Set token data
        _tokenData[membershipTokenId].appId = appId;
        _tokenData[membershipTokenId].tokenType = TokenType.MEMBERSHIP;
        _tokenData[membershipTokenId].inviter = inviter;
        
        // Grant invites to the new user
        _appData[appId].invitesLeft[msg.sender] = _appData[appId].invitesPerNewUser;
        
        emit InviteAccepted(appId, msg.sender, inviter, membershipTokenId);
    }
    
    /**
     * @dev Overrides transferFrom to respect app transferrability settings for membership tokens.
     * Invitation tokens can always be transferred.
     */
    function transferFrom(
        address from, 
        address to, 
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721) {
        TokenData storage data = _tokenData[tokenId];
        
        // If it's an invitation token, allow transfer
        if (data.tokenType == TokenType.INVITATION) {
            super.transferFrom(from, to, tokenId);
            return;
        }
        
        // For membership tokens, check transferrability
        bytes32 appId = data.appId;
        require(_appData[appId].isTransferrable, "App not transferrable");
        require(!data.locked, "Token transfer locked");
        super.transferFrom(from, to, tokenId);
    }
    
    /**
     * @dev Overrides safeTransferFrom to respect app transferrability settings for membership tokens.
     * Invitation tokens can always be transferred.
     */
    function safeTransferFrom(
        address from, 
        address to, 
        uint256 tokenId, 
        bytes memory data
    ) public override(ERC721Upgradeable, IERC721) {
        TokenData storage tokenData = _tokenData[tokenId];
        
        // If it's an invitation token, allow transfer
        if (tokenData.tokenType == TokenType.INVITATION) {
            super.safeTransferFrom(from, to, tokenId, data);
            return;
        }
        
        // For membership tokens, check transferrability
        bytes32 appId = tokenData.appId;
        require(_appData[appId].isTransferrable, "App not transferrable");
        require(!tokenData.locked, "Token transfer locked");
        super.safeTransferFrom(from, to, tokenId, data);
    }
    
    /**
     * @dev Sets whether membership NFTs for an app can be transferred.
     * Note that invitation NFTs can always be transferred.
     * @param appId The app ID
     * @param _isTransferrable Whether tokens can be transferred
     */
    function setTransferrable(bytes32 appId, bool _isTransferrable) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        _appData[appId].isTransferrable = _isTransferrable;
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
        _appData[appId].invitesPerNewUser = _invites;
    }
    
    /**
     * @dev Grants additional invites to a user.
     * @param appId The app ID
     * @param user User to receive invites
     * @param amount Number of invites to grant
     */
    function grantInvites(bytes32 appId, address user, uint256 amount) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        require(_appData[appId].registered[user], "User not registered");
        require(amount <= 1000, "Too many invites"); // Sanity check
        
        _appData[appId].invitesLeft[user] += amount;
        emit InvitesGranted(appId, user, amount);
    }
    
    /**
     * @dev Returns metadata URI for a specific token.
     * @param tokenId The token ID
     * @return Token URI string
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Verify token exists
        _requireOwned(tokenId);
        
        TokenData storage data = _tokenData[tokenId];
        bytes32 appId = data.appId;
        string memory base = _appData[appId].baseURI;
        string memory tokenTypeStr = data.tokenType == TokenType.INVITATION ? "invite" : "member";
        
        if (bytes(base).length > 0) {
            return string(abi.encodePacked(base, tokenTypeStr, "/", tokenId.toString()));
        }
        
        // Default fallback
        return string(abi.encodePacked("https://chainviti.xyz/metadata/", tokenTypeStr, "/", tokenId.toString()));
    }
    
    /**
     * @dev Sets the base URI for token metadata for an app.
     * @param appId The app ID
     * @param baseURI The base URI for metadata
     */
    function setAppBaseURI(bytes32 appId, string memory baseURI) external {
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        _appData[appId].baseURI = baseURI;
        emit BaseURISet(appId, baseURI);
    }
    
    /**
     * @dev Checks if a user has access to an app.
     * @param appId The app ID
     * @param user User address to check
     * @return True if user has access
     */
    function hasAccess(bytes32 appId, address user) public view returns (bool) {
        // Direct registration check for efficiency
        if (_appData[appId].registered[user]) {
            return true;
        }
        
        // Token-based check (less efficient for users with many tokens)
        uint256 balance = balanceOf(user);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (_tokenData[tokenId].appId == appId && _tokenData[tokenId].tokenType == TokenType.MEMBERSHIP) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Checks if a user has an invitation to an app.
     * @param appId The app ID
     * @param user User address to check
     * @return True if user has an invitation
     */
    function hasInvitation(bytes32 appId, address user) public view returns (bool) {
        uint256 balance = balanceOf(user);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (_tokenData[tokenId].appId == appId && _tokenData[tokenId].tokenType == TokenType.INVITATION) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Returns all invitation token IDs owned by a user for a specific app.
     * @param appId The app ID
     * @param user User address to check
     * @return Array of invitation token IDs
     */
    function getInvitationTokens(bytes32 appId, address user) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory result = new uint256[](balance);
        uint256 count = 0;
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (_tokenData[tokenId].appId == appId && _tokenData[tokenId].tokenType == TokenType.INVITATION) {
                result[count] = tokenId;
                count++;
            }
        }
        
        // Resize the array to the actual count
        uint256[] memory finalResult = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            finalResult[i] = result[i];
        }
        
        return finalResult;
    }
    
    /**
     * @dev Transfers ownership of an app to a new owner.
     * @param appId The app ID
     * @param newOwner New owner address
     */
    function transferAppOwnership(bytes32 appId, address newOwner) external {
        require(msg.sender == _appData[appId].owner, "Not app owner");
        require(newOwner != address(0), "Invalid new owner");
        
        _appData[appId].owner = newOwner;
        
        // Make new owner an admin if not already
        if (!_appData[appId].admins[newOwner]) {
            _appData[appId].admins[newOwner] = true;
        }
        
        emit AppOwnershipTransferred(appId, newOwner);
    }
    
    /**
     * @dev Adds an admin to an app.
     * @param appId The app ID
     * @param admin Admin address to add
     */
    function addAdmin(bytes32 appId, address admin) external {
        require(msg.sender == _appData[appId].owner, "Not app owner");
        require(admin != address(0), "Invalid admin address");
        
        _appData[appId].admins[admin] = true;
        emit AdminAdded(appId, admin);
    }
    
    /**
     * @dev Removes an admin from an app.
     * @param appId The app ID
     * @param admin Admin address to remove
     */
    function removeAdmin(bytes32 appId, address admin) external {
        require(msg.sender == _appData[appId].owner, "Not app owner");
        require(admin != _appData[appId].owner, "Cannot remove owner as admin");
        
        _appData[appId].admins[admin] = false;
        emit AdminRemoved(appId, admin);
    }
    
    /**
     * @dev Locks or unlocks a specific membership token from being transferred.
     * Note: Invitation tokens cannot be locked.
     * @param tokenId Token to lock/unlock
     * @param locked Whether to lock the token
     */
    function setTokenLocked(uint256 tokenId, bool locked) external {
        _requireOwned(tokenId);
        require(_tokenData[tokenId].tokenType == TokenType.MEMBERSHIP, "Can only lock membership tokens");
        
        bytes32 appId = _tokenData[tokenId].appId;
        require(_isAppAdmin(appId, msg.sender), "Not app admin");
        
        _tokenData[tokenId].locked = locked;
        emit TokenLocked(tokenId, locked);
    }
    
    /**
     * @dev Batch invite multiple users at once (gas optimization).
     * @param appId The app ID
     * @param recipients Array of addresses to receive invitations
     */
    function batchInvite(bytes32 appId, address[] calldata recipients) external {
        require(_appData[appId].registered[msg.sender], "You are not registered");
        require(_appData[appId].invitesLeft[msg.sender] >= recipients.length, "Not enough invites");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            require(recipient != address(0), "Invalid address");
            
            // Mint an invitation token
            uint256 invitationTokenId = _tokenIdCounter;
            _tokenIdCounter++;
            
            _safeMint(recipient, invitationTokenId);
            _tokenData[invitationTokenId].appId = appId;
            _tokenData[invitationTokenId].tokenType = TokenType.INVITATION;
            _tokenData[invitationTokenId].inviter = msg.sender;
            
            emit InviteSent(appId, msg.sender, recipient, invitationTokenId);
        }
        
        _appData[appId].invitesLeft[msg.sender] -= recipients.length;
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
        return user == _appData[appId].owner || _appData[appId].admins[user];
    }
    
    /**
     * @dev Implement required function to resolve inheritance conflicts
     */
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        address from = super._update(to, tokenId, auth);
        
        // Update registration status if this is a transfer of a membership token
        if (from != address(0) && to != address(0) && _tokenData[tokenId].tokenType == TokenType.MEMBERSHIP) {
            bytes32 appId = _tokenData[tokenId].appId;
            _appData[appId].registered[to] = true;
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
    
    /**
     * @dev Public accessor for registered status
     */
    function isRegistered(bytes32 appId, address user) external view returns (bool) {
        return _appData[appId].registered[user];
    }
    
    /**
     * @dev Public accessor for invites left
     */
    function getInvitesLeft(bytes32 appId, address user) external view returns (uint256) {
        return _appData[appId].invitesLeft[user];
    }
    
    /**
     * @dev Public accessor for app owner
     */
    function getAppOwner(bytes32 appId) external view returns (address) {
        return _appData[appId].owner;
    }
    
    /**
     * @dev Public accessor for app transferrability
     */
    function isAppTransferrable(bytes32 appId) external view returns (bool) {
        return _appData[appId].isTransferrable;
    }
    
    /**
     * @dev Public accessor for app base URI
     */
    function getAppBaseURI(bytes32 appId) external view returns (string memory) {
        return _appData[appId].baseURI;
    }
    
    /**
     * @dev Public accessor for invites per new user
     */
    function getInvitesPerNewUser(bytes32 appId) external view returns (uint256) {
        return _appData[appId].invitesPerNewUser;
    }
    
    /**
     * @dev Public accessor for token app ID
     */
    function getTokenAppId(uint256 tokenId) external view returns (bytes32) {
        return _tokenData[tokenId].appId;
    }
    
    /**
     * @dev Public accessor for token type
     */
    function getTokenType(uint256 tokenId) external view returns (TokenType) {
        return _tokenData[tokenId].tokenType;
    }
    
    /**
     * @dev Public accessor for token inviter
     */
    function getInviterOf(uint256 tokenId) external view returns (address) {
        return _tokenData[tokenId].inviter;
    }
    
    /**
     * @dev Public accessor for token locked status
     */
    function isTokenLocked(uint256 tokenId) external view returns (bool) {
        return _tokenData[tokenId].locked;
    }
}