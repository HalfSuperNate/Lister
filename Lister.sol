// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.23;

import {ERC721PsiBurnable, ERC721Psi} from "./ERC721Psi/extension/ERC721PsiBurnable.sol";
import {Admins} from "./Admins.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";

/// @author developer's github https://github.com/HalfSuperNate
contract Lister is ERC721PsiBurnable, ReentrancyGuard, Admins {
    using LibString for uint256;
    using LibString for string;
    using Base64 for *;

    mapping(uint256 => address[]) public listID;
    mapping(address => mapping(uint256 => bool)) public listed;
    mapping(address => mapping(uint256 => uint256)) public sentValue;
    mapping(uint256 => bool) public trackValue;
    mapping(uint256 => bool) public isActiveList;
    mapping(uint256 => uint256) public cost;
    mapping(uint256 => uint256) public limit;
    mapping(uint256 => uint256) public tokenListID;
    mapping(uint256 => uint256) public listIDToken;
    mapping(uint256 => uint256[2]) public timer;
    mapping(uint256 => string) public listName;
    mapping(uint256 => string) public listDescription;
    mapping(uint256 => string) public listImage;
    mapping(uint256 => string) public listAnimation;
    uint256 public registeryCost;
    uint256 public listCount;
    uint256 public featuredList;
    uint256 public vaultBalance;
    address public vault;
    bool public paused;

    error AlreadyListed();
    error CannotBeZeroAddress();
    error Closed();
    error InvalidUser();
    error NotListed();
    error Paused();
    error TimeEnded();
    error TimeNotStarted();
    error Unavailable();
    error ValueRequired();
    
    constructor(string memory name, string memory symbol) ERC721Psi(name, symbol) Admins(msg.sender) {
        init();
    }

    function init() internal {
        if (listCount > 0) revert Unavailable();
        vault = msg.sender;
        _mint(msg.sender, 1); //mints the 0 token
        paused = true;
    }

    /**
     * @dev Returns metadata uri for a token ID.
     * @param tokenId The token ID to fetch metadata uri.
     */
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        if (!_exists(tokenId)) revert Unavailable();
        uint256 _ID = listIDToken[tokenId];

        string memory json = Base64.encode(bytes(string(abi.encodePacked(
        '{"name": "', 
        listName[_ID], 
        ' #', 
        tokenId.toString(), 
        '", "description": "', 
        listDescription[_ID], 
        '", "image": "', 
        listImage[_ID], 
        '", "animation_url": "', 
        listAnimation[_ID], 
        '"}'))));

        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    /**
     * @dev User can set metadata for the specified list.
     * @param _ID The list ID to edit.
     * @param _metadata [name, description, image, animation].
     */
    function setListMetadata(uint256 _ID, string[4] calldata _metadata) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        listName[_ID] = _metadata[0];
        listDescription[_ID] = _metadata[1];
        listImage[_ID] = _metadata[2];
        listAnimation[_ID] = _metadata[3];
    }

    /**
     * @dev User can register to own the specified list if available.
     * @param _ID The list ID to register.
     */
    function registerList(uint256 _ID) external payable nonReentrant {
        if (paused) revert Paused();
        if (listIDToken[_ID] != 0) revert Unavailable();
        if (registeryCost != 0) {
            if (msg.value < registeryCost) revert ValueRequired();
            vaultBalance += msg.value;
        }
        listCount++;
        tokenListID[listCount] = _ID;
        listIDToken[_ID] = listCount;
        _mint(msg.sender, 1);
    }

    /**
     * @dev Get list owner of the specified list.
     * @param _ID The list ID to check.
     */
    function listOwnerByID(uint256 _ID) public view returns(address) {
        uint256 _tokenID = listIDToken[_ID];
        return ownerOf(_tokenID);
    }

    /**
     * @dev Check if caller is list owner or admin of the specified list.
     * @param _ID The list ID to check.
     */
    function isListOwnerAdmin(uint256 _ID) public view returns(bool) {
        if (checkIfAdmin()) {
            return true;
        }
        return listOwnerByID(_ID) == msg.sender;
    }

    /**
     * @dev User can check if an address is on the specified list.
     * @param _ID The list ID to get.
     * @param _address The address to check.
     */
    function checkIsListed(uint256 _ID, address _address) external view returns(bool) {
        return listed[_address][_ID];
    }

    /**
     * @dev User can check the value an address sent for the specified list.
     * @param _ID The list ID to get.
     * @param _address The address to check.
     */
    function checkSentValue(uint256 _ID, address _address) external view returns(uint256) {
        return sentValue[_address][_ID];
    }

    /**
     * @dev User can get a list of addresses on the specified list.
     * @param _ID The list ID to get.
     */
    function getList(uint256 _ID) external view returns(address[] memory) {
        return listID[_ID];
    }

    /**
     * @dev User can get a list of values sent on the specified list if tracked.
     * @param _ID The list ID to get.
     */
    function getSentValues(uint256 _ID) public view returns(uint256[] memory) {
        uint256[] memory _values = new uint256[](listID[_ID].length);
        for (uint256 i = 0; i < listID[_ID].length; i++) {
            _values[i] = sentValue[listID[_ID][i]][_ID];
        }
        return _values;
    }

    /**
     * @dev User can get a total value sent for the specified list if tracked.
     * @param _ID The list ID to get.
     */
    function getSentTotal(uint256 _ID) public view returns(uint256) {
        uint256 _total;
        uint256[] memory _values = getSentValues(_ID);
        for (uint256 i = 0; i < _values.length; i++) {
            _total += _values[i];
        }
        return _total;
    }

    /**
     * @dev User can get a start and end time for the specified list.
     * @param _ID The list ID to get.
     */
    function getTimes(uint256 _ID) external view returns(uint256[2] memory) {
        return timer[_ID];
    }

    /**
     * @dev List Owner or Admin can configure a list.
     * @param _ID The list ID to edit.
     * @param _config Config [activeState, trackValue, cost, limit, timerStart, timerEnd].
     * Note: 0 = false, 1 = true
     */
    function setListConfig(uint256 _ID, uint256[6] calldata _config) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        isActiveList[_ID] = _config[0] == 1;
        trackValue[_ID] = _config[1] == 1;
        cost[_ID] = _config[2];
        limit[_ID] = _config[3];
        timer[_ID][0] = _config[4];
        timer[_ID][0] = _config[5];
    }

    /**
     * @dev List Owner or Admin can set cost for users to get on the list.
     * @param _ID The list ID to edit.
     * @param _cost Cost for getting listed.
     */
    function setListCost(uint256 _ID, uint256 _cost) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        cost[_ID] = _cost;
    }

    /**
     * @dev List Owner or Admin can set if a list has a limit.
     * @param _ID The list ID to edit.
     * @param _limit Limit at 0 is limitless, otherwise limited at limit.
     */
    function setListLimit(uint256 _ID, uint256 _limit) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        limit[_ID] = _limit;
    }

    /**
     * @dev List Owner or Admin can set if a list has a start and stop time.
     * @param _ID The list ID to edit.
     * @param _StartEndTime 0 ignores timer, otherwise start at time[0] stop at time[1].
     */
    function setListTimer(uint256 _ID, uint256[2] calldata _StartEndTime) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        timer[_ID] = _StartEndTime;
    }

    /**
     * @dev List Owner or Admin can set if a list is active & set if a list is tracking value sent.
     * @param _ID The list ID to edit.
     * @param _state Flag true for active false for closed.
     */
    function setListState(uint256 _ID, bool _state) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        isActiveList[_ID] = _state;
    }

    /**
     * @dev List Owner or Admin can set if a list is tracking value sent.
     * @param _ID The list ID to edit.
     * @param _state Flag true for tracking false for not.
     */
    function setTrackValueState(uint256 _ID, bool _state) public {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        trackValue[_ID] = _state;
    }

    /**
     * @dev Admin can set a featured list.
     * @param _ID The list ID.
     */
    function setFeaturedList(uint256 _ID) public onlyAdmins {
        featuredList = _ID;
    }

    /**
     * @dev List Owner or Admin can add an address to a specified list.
     * @param _ID The list ID to get listed on.
     * @param _address The address to list.
     */
    function listSpecified(uint256 _ID, address _address) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        if (listed[_address][_ID]) revert AlreadyListed();
        if (limit[_ID] != 0 && listID[_ID].length >= limit[_ID]) revert Closed();
        listed[_address][_ID] = true;
        listID[_ID].push(_address);
    }

    /**
     * @dev User can get listed on a specified list.
     * @param _ID The list ID to get listed on.
     */
    function listMeSpecified(uint256 _ID) public payable {
        if (listed[msg.sender][_ID]) revert AlreadyListed();
        if (!isActiveList[_ID]) revert Closed();
        if (timer[_ID][0] != 0 && block.timestamp < timer[_ID][0]) revert TimeNotStarted();
        if (timer[_ID][1] != 0 && block.timestamp > timer[_ID][1]) revert TimeEnded();
        if (limit[_ID] != 0 && listID[_ID].length >= limit[_ID]) revert Closed();
        if (msg.value < cost[_ID]) revert ValueRequired();
        listed[msg.sender][_ID] = true;
        listID[_ID].push(msg.sender);
        if (trackValue[_ID]) {
            sentValue[msg.sender][_ID] = msg.value;
        }
    }

    /**
     * @dev User can get listed on the featured list.
     */
    function listMe() external payable {
        listMeSpecified(featuredList);
    }

    /**
     * @dev User can increase value sent if already listed on the specified list.
     * @param _ID The list ID to increase value on.
     Note: User can only increase value within the timeframe and if the list is not closed.
     */
    function increaseSentValue(uint256 _ID) external payable {
        if (msg.value == 0) revert ValueRequired();
        if (!listed[msg.sender][_ID]) revert NotListed();
        if (!isActiveList[_ID]) revert Closed();
        if (timer[_ID][1] != 0 && block.timestamp > timer[_ID][1]) revert TimeEnded();
        sentValue[msg.sender][_ID] += msg.value;
    }

    /**
     * @dev Admin can set pause state.
     * @param _pause Set to true for paused and false for unpause.
     */
    function setPause(bool _pause) external onlyAdmins{
        paused = _pause;
    }

    /**
     * @dev Admin can set registery cost.
     * @param _cost Cost for minting a list.
     */
    function setRegisteryCost(uint256 _cost) external onlyAdmins{
        registeryCost = _cost;
    }

    /**
     * @dev Allow admins to set a new vault address.
     * @param _newVault New vault to set.
     */
    function setVault(address _newVault) public onlyAdmins {
        if (_newVault == address(0)) revert CannotBeZeroAddress();
        vault = _newVault;
    }

    /**
     * @dev Pull list funds.
     */
    function withdraw(uint256 _ID) external nonReentrant {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        (bool success, ) = payable(msg.sender).call{ value: getSentTotal(_ID) } ("");
        require(success);
    }

    /**
     * @dev Pull vaulted funds to the vault.
     */
    function withdrawVault() external nonReentrant {
        if (vault == address(0)) revert CannotBeZeroAddress();
        (bool success, ) = payable(vault).call{ value: vaultBalance } ("");
        require(success);
        vaultBalance = 0;
    }
}
