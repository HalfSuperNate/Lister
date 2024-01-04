// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.23;

import {ERC721PsiBurnable, ERC721Psi} from "./ERC721Psi/extension/ERC721PsiBurnable.sol";
import {Admins} from "./Admins.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";

/// @author developer's github https://github.com/HalfSuperNate
contract ChainList is ERC721PsiBurnable, ReentrancyGuard, Admins {
    using LibString for *;
    using Base64 for *;

    mapping(address => mapping(uint256 => bool)) private listed;
    mapping(address => mapping(uint256 => uint256)) private sentValue;
    mapping(uint256 => uint256) private sentValueTotal;
    mapping(uint256 => uint256) private releasedValueTotal;
    mapping(uint256 => uint256) public tokenListID; //gets list ID by tokenId
    mapping(uint256 => uint256) public listIDToken; //gets tokenId by list ID
    mapping(uint256 => List) public list; //gets list data by list ID

    uint256 public registeryCost;
    uint256 public listCount;
    uint256 public featuredList;
    uint256[3] public feeTier; // [default, tier_1, tier_2]
    uint256[4] public feeTierLimits; // [tier_1_listed, tier_1_sent, tier_2_listed, tier_2_sent]
    uint256 public vaultBalance;
    address public vault;
    bool public paused;

    struct List {
        bool isActive;
        uint256 cost;
        uint256 limit;
        uint256 attributeLimit;
        uint256[2] timer;
        string title; //name
        string description;
        string image;
        string animation;
        string externalURL;
        Attribute[] attributes;
        mapping(uint256 => Verify) verify;
        uint256 verifyCount;
        address[] listee;
    }

    struct Attribute {
        uint8 display; // 0=string, 1=int_float, 2="boost_number", 3="boost_percentage", 4="number", 5="date"
        string trait; // "string" or "" for null
        string value;
    }

    struct Verify {
        bytes32 root;
        mapping(string => bool) secretUsed;
    }

    error AlreadyListed();
    error CannotBeZeroAddress();
    error Closed();
    error IndexOutOfRange();
    error InvalidUser();
    error NotListed();
    error Paused();
    error TimeEnded();
    error TimeNotStarted();
    error Unavailable();
    error ValueRequired();
    error VerificationError();
    
    constructor(string memory name, string memory symbol) ERC721Psi(name, symbol) Admins(msg.sender) {
        init();
    }

    function init() internal {
        if (totalSupply() > 0) revert Unavailable();
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
        uint256 _ID = tokenListID[tokenId];

        string memory json = Base64.encode(bytes(string.concat(
        '{"name": "', 
        getListName(_ID), 
        '", "description": "', 
        getListDescription(_ID), 
        '", "image": "', 
        list[_ID].image, 
        '", "animation_url": "', 
        list[_ID].animation,
        '", "external_url": "', 
        list[_ID].externalURL,
        '", "attributes": ', 
        getListAttributes(_ID),
        '}')));

        return string.concat('data:application/json;base64,', json);
    }

    function getListName(uint256 _ID) public view returns (string memory) {
        string memory _result = compareStrings(list[_ID].title,"") ? string.concat("#", _ID.toString()) : string.concat(list[_ID].title, " #", _ID.toString());

        return _result;
    }

    function getListDescription(uint256 _ID) public view returns (string memory) {
        string memory _result = compareStrings(list[_ID].description,"") ? string.concat("### ", getListName(_ID), "\\n\\n---\\n") : string.concat("### ", getListName(_ID), "\\n\\n", list[_ID].description, "\\n\\n---\\n");

        return _result;
    }

    function getListAttributes(uint256 _ID) public view returns (string memory) {
        string memory _result;
        if (list[_ID].attributes.length != 0) {
            for (uint256 i = 0; i < list[_ID].attributes.length; i++) {
                _result = string.concat(_result, "{", getDisplayType(_ID,i), getTraitType(_ID,i), getTraitValue(_ID,i), "},");
            }
        }
        if (list[_ID].listee.length == 0) {
            _result = string.concat(_result, '{"value":"0x0000000000000000000000000000000000000000"}');
        } else{
            for (uint256 i = 0; i < list[_ID].listee.length; i++) {
                if (list[_ID].attributeLimit != 0 && (i + list[_ID].attributes.length) >= list[_ID].attributeLimit) {
                    _result = string.concat(_result, '{"trait_type":"*Continued*","value":"*See List Viewer*"}');
                    break;
                }
                if (i == list[_ID].listee.length - 1) {
                    _result = string.concat(_result, '{"value":"', list[_ID].listee[i].toHexString(), '"}');
                } else{
                    _result = string.concat(_result, '{"value":"', list[_ID].listee[i].toHexString(), '"},');
                }
            }
        }
        
        return string.concat("[", _result, "]");
    }
    
    function getDisplayType(uint256 _ID, uint256 _index) public view returns (string memory) {
        if (_index > list[_ID].attributes.length - 1) revert IndexOutOfRange();
        if (list[_ID].attributes[_index].display <= 1) return "";
        if (list[_ID].attributes[_index].display == 2) return '"display_type":"boost_number",';
        if (list[_ID].attributes[_index].display == 3) return '"display_type":"boost_percentage",';
        if (list[_ID].attributes[_index].display == 4) return '"display_type":"number",';
        if (list[_ID].attributes[_index].display == 5) return '"display_type":"date",';
        return "";
    }

    function getTraitType(uint256 _ID, uint256 _index) public view returns (string memory) {
        if (_index > list[_ID].attributes.length - 1) revert IndexOutOfRange();
        string memory _result = compareStrings(list[_ID].attributes[_index].trait,"") ? "" : string.concat('"trait_type":"', list[_ID].attributes[_index].trait, '",');
        return _result;
    }

    function getTraitValue(uint256 _ID, uint256 _index) public view returns (string memory) {
        if (_index > list[_ID].attributes.length - 1) revert IndexOutOfRange();
        string memory _result = list[_ID].attributes[_index].display == 0 ? string.concat('"value":"', list[_ID].attributes[_index].value, '"') : string.concat('"value":', list[_ID].attributes[_index].value);
        return _result;
    }

    /**
     * @dev User can set new attributes for the specified list.
     * @param _ID The list ID to edit.
     * @param _displayType Use 0=string, 1=int_float, 2="boost_number", 3="boost_percentage", 4="number", 5="date".
     * @param _traitType Use "string" or "" for null.
     * @param _traitValue Use "string" if displayType is 0 or "numbers" for displayTypes 1-4, for option 5 use "unixTimeStampNumber".
     * Note: Example: 0, [0,1,2,3,4,5], ["","Lvl","Str","Hp","Mp","Birthday"], ["John","1.8","66","4","20","1703901173"]
     */
    function setListAttributes(uint256 _ID, uint8[] calldata _displayType, string[] calldata _traitType, string[] calldata _traitValue) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        delete list[_ID].attributes;
        Attribute memory newAttribute = Attribute({
            display: 0,
            trait: "",
            value: ""
        });
        for (uint256 i = 0; i < _displayType.length; i++) {
            newAttribute.display = _displayType[i];
            newAttribute.trait = _traitType[i];
            newAttribute.value = _traitValue[i];
            list[_ID].attributes.push(newAttribute);
        }
    }

    /**
     * @dev User can set metadata for the specified list.
     * @param _ID The list ID to edit.
     * @param _metadata [name, description, image, animation, externalURL].
     */
    function setListMetadata(uint256 _ID, string[5] calldata _metadata) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        if (!compareStrings(_metadata[0],"")){
            list[_ID].title = _metadata[0];
        }
        if (!compareStrings(_metadata[1],"")){
            list[_ID].description = _metadata[1];
        }
        if (!compareStrings(_metadata[2],"")){
            list[_ID].image = _metadata[2];
        }
        if (!compareStrings(_metadata[3],"")){
            list[_ID].animation = _metadata[3];
        }
        if (!compareStrings(_metadata[4],"")){
            list[_ID].externalURL = _metadata[4];
        }
    }

    /**
     * @dev User can register to own the specified list if available.
     * @param _ID The unique list ID to register.
     */
    function registerList(uint256 _ID) external payable nonReentrant {
        if (listIDToken[_ID] != 0 || _ID == 0) revert Unavailable();
        if (paused) revert Paused();
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
        return list[_ID].listee;
    }

    /**
     * @dev User can get a list of values sent on the specified list if tracked.
     * @param _ID The list ID to get.
     */
    function getSentValues(uint256 _ID) public view returns(uint256[] memory) {
        uint256[] memory _values = new uint256[](list[_ID].listee.length);
        for (uint256 i = 0; i < list[_ID].listee.length; i++) {
            _values[i] = sentValue[list[_ID].listee[i]][_ID];
        }
        return _values;
    }

    /**
     * @dev User can get a total value sent for the specified list.
     * @param _ID The list ID to get.
     */
    function getSentTotal(uint256 _ID) external view returns(uint256) {
        return sentValueTotal[_ID];
    }

    /**
     * @dev User can get a total value released for the specified list.
     * @param _ID The list ID to get.
     */
    function getReleasedTotal(uint256 _ID) external view returns(uint256) {
        return releasedValueTotal[_ID];
    }

    /**
     * @dev User can get a releasable balance for the specified list.
     * @param _ID The list ID to get.
     */
    function getReleasableTotal(uint256 _ID) external view returns(uint256) {
        return sentValueTotal[_ID] - releasedValueTotal[_ID];
    }

    /**
     * @dev User can get a start and end time for the specified list.
     * @param _ID The list ID to get.
     */
    function getTimes(uint256 _ID) external view returns(uint256[2] memory) {
        return list[_ID].timer;
    }

    /**
     * @dev List Owner or Admin can configure a list.
     * @param _ID The list ID to edit.
     * @param _config Config [activeState, cost, limit, timerStart, timerEnd].
     * Note: 0 = false, 1 = true. Example for a free no cost no limits list: 0, [1,0,0,0,0]
     */
    function setListConfig(uint256 _ID, uint256[5] calldata _config) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].isActive = _config[0] == 1;
        list[_ID].cost = _config[1];
        list[_ID].limit = _config[2];
        list[_ID].timer[0] = _config[3];
        list[_ID].timer[1] = _config[4];
    }

    /**
     * @dev List Owner or Admin can set cost for users to get on the list.
     * @param _ID The list ID to edit.
     * @param _cost Cost for getting listed.
     */
    function setListCost(uint256 _ID, uint256 _cost) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].cost = _cost;
    }

    /**
     * @dev List Owner or Admin can set if a list has a limit.
     * @param _ID The list ID to edit.
     * @param _limit Limit at 0 is limitless, otherwise limited at limit.
     */
    function setListLimit(uint256 _ID, uint256 _limit) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].limit = _limit;
    }

    /**
     * @dev List Owner or Admin can set if a list has a start and stop time.
     * @param _ID The list ID to edit.
     * @param _StartEndTime 0 ignores timer, otherwise start at time[0] stop at time[1].
     */
    function setListTimer(uint256 _ID, uint256[2] calldata _StartEndTime) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].timer = _StartEndTime;
    }

    /**
     * @dev List Owner or Admin can set if a list is active & set if a list is tracking value sent.
     * @param _ID The list ID to edit.
     * @param _state Flag true for active false for closed.
     */
    function setListState(uint256 _ID, bool _state) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].isActive = _state;
    }

    /**
     * @dev List Owner or Admin can set a root if the list has secret entry codes.
     * @param _ID The list ID to edit.
     * @param _root Root for verification.
     * Note: Once a user enters a list with a secret, that secret is not longer usable for that list.
     * Warning: Setting a root resets all previously used secrets.
     */
    function setListRoot(uint256 _ID, bytes32 _root) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].verifyCount++;
        list[_ID].verify[list[_ID].verifyCount].root = _root;
    }

    /**
     * @dev List Owner or Admin can set an attribute limit if a marketplace restricts attribute count.
     * @param _ID The list ID to edit.
     * @param _limit The limit to set.
     */
    function setAttributeLimit(uint256 _ID, uint256 _limit) external {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        list[_ID].attributeLimit = _limit;
    }

    /**
     * @dev Admin can set a featured list.
     * @param _ID The list ID.
     */
    function setFeaturedList(uint256 _ID) public onlyAdmins {
        featuredList = _ID;
    }

    /**
     * @dev List Owner or Admin can add or remove an address on a specified list.
     * @param _ID The list ID to edit.
     * @param _address The address to add or remove.
     * @param _addRemove Flag true to add address, false to remove address.
     * Note: An address can only be added if the limit is not reached.
     */
    function listSpecifiedAddRemove(uint256 _ID, address _address, bool _addRemove) external nonReentrant {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        if (_addRemove) {
            if (listed[_address][_ID]) revert AlreadyListed();
            if (list[_ID].limit != 0 && list[_ID].listee.length >= list[_ID].limit) revert Closed();
            listed[_address][_ID] = true;
            list[_ID].listee.push(_address);
        } else{
            if (!listed[_address][_ID]) revert NotListed();
            listed[_address][_ID] = false;
            (list[_ID].listee[getIndexOfUserOnList(_ID, _address)], list[_ID].listee[list[_ID].listee.length - 1]) = (list[_ID].listee[list[_ID].listee.length - 1], list[_ID].listee[getIndexOfUserOnList(_ID, _address)]);
            list[_ID].listee.pop();
        }
    }

    /**
     * @dev User can get listed on a specified list.
     * @param _ID The list ID to get listed on.
     */
    function listMeSpecified(uint256 _ID) public payable nonReentrant {
        if (msg.value < list[_ID].cost) revert ValueRequired();
        if (listed[msg.sender][_ID]) revert AlreadyListed();
        if (!list[_ID].isActive) revert Closed();
        if (list[_ID].timer[0] != 0 && block.timestamp < list[_ID].timer[0]) revert TimeNotStarted();
        if (list[_ID].timer[1] != 0 && block.timestamp > list[_ID].timer[1]) revert TimeEnded();
        if (list[_ID].limit != 0 && list[_ID].listee.length >= list[_ID].limit) revert Closed();
        listed[msg.sender][_ID] = true;
        list[_ID].listee.push(msg.sender);
        if (msg.value > 0) {
            sentValue[msg.sender][_ID] = msg.value;
            sentValueTotal[_ID] += msg.value;
        }
    }

    /**
     * @dev User can get listed on the featured list.
     */
    function listMe() external payable {
        listMeSpecified(featuredList);
    }

    /**
     * @dev User can get listed on the specified list with a secret proof.
     * @param _ID The list ID to get listed on.
     * @param _secret Secret to check.
     * @param _proof bytes32 array for proof.
     */
    function listEnterSecret(uint256 _ID, string memory _secret, bytes32[] memory _proof) external payable {
        if (list[_ID].verify[list[_ID].verifyCount].secretUsed[_secret]) revert AlreadyListed();
        if (!verifyUser(_proof, _ID, _secret)) revert VerificationError();
        list[_ID].verify[list[_ID].verifyCount].secretUsed[_secret] = true;
        listMeSpecified(_ID);
    }

    /**
     * @dev Verify if user is allowed on the list.
     * @param proof bytes32 array for proof.
     * @param _ID Batch ID to get root.
     * @param _secret Secret to check.
     */
    function verifyUser(bytes32[] memory proof, uint256 _ID, string memory _secret) public view returns (bool) {
        if (proof.length != 0){
            if (MerkleProof.verify(proof, list[_ID].verify[list[_ID].verifyCount].root, keccak256(abi.encodePacked(_secret)))) {
                return (true);
            }
        }
        return (false);
    }

    /**
     * @dev User can removed their address from a specified list.
     * @param _ID The list ID to get removed from.
     */
    function removeMeSpecified(uint256 _ID) public nonReentrant {
        if (!listed[msg.sender][_ID]) revert NotListed();
        listed[msg.sender][_ID] = false;
        (list[_ID].listee[getIndexOfUserOnList(_ID, msg.sender)], list[_ID].listee[list[_ID].listee.length - 1]) = (list[_ID].listee[list[_ID].listee.length - 1], list[_ID].listee[getIndexOfUserOnList(_ID, msg.sender)]);
        list[_ID].listee.pop();
    }

    /**
     * @dev User can get the index of address from a specified list.
     * @param _ID The list ID to get index from.
     * @param _user The address to get index of.
     */
    function getIndexOfUserOnList(uint256 _ID, address _user) public view returns(uint256) {
        for (uint256 i = 0; i < list[_ID].listee.length; i++) {
            if (list[_ID].listee[i] == _user) return i;
        }
        revert NotListed();
    }

    /**
     * @dev User can removed their address from the featured list.
     */
    function removeMe() external payable {
        removeMeSpecified(featuredList);
    }

    /**
     * @dev User can increase value sent if already listed on the specified list.
     * @param _ID The list ID to increase value on.
     Note: User can only increase value within the timeframe and if the list is not closed.
     */
    function increaseSentValue(uint256 _ID) external payable {
        if (msg.value == 0) revert ValueRequired();
        if (!listed[msg.sender][_ID]) revert NotListed();
        if (!list[_ID].isActive) revert Closed();
        if (list[_ID].timer[1] != 0 && block.timestamp > list[_ID].timer[1]) revert TimeEnded();
        sentValue[msg.sender][_ID] += msg.value;
        sentValueTotal[_ID] += msg.value;
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
     * @dev User can get the fee percentage for a specified list.
     * @param _ID The list ID to get fee.
     * Note: To get true percentage divide returned value by 1000.
     */
    function getFeePercentage(uint256 _ID) public view returns(uint256) {
        // fees are based on a 3 tier system 
        // a default percentage fee is taken on withdrawl
        if (list[_ID].listee.length < feeTierLimits[0] || sentValueTotal[_ID] < feeTierLimits[1]) {
            return feeTier[0];
        }
        // if sent total passes x ETH or y listed the percentage is set to tier 1
        if (list[_ID].listee.length < feeTierLimits[2] || sentValueTotal[_ID] < feeTierLimits[3]) {
            return feeTier[1];
        }
        // if sent total passes z ETH or w listed the percentage caps at tier 2
        return feeTier[2];
    }

    /**
     * @dev Admin can set fee tier costs and limits.
     * @param _config New fee config.
     * Note: feeTier = [default, tier_1, tier_2], feeTierLimits = [tier_1_listed, tier_1_sent, tier_2_listed, tier_2_sent]
     */
    function setFeeConfig(uint256[7] calldata _config) external onlyAdmins {
        feeTier[0] = _config[0]; // default
        feeTier[1] = _config[1]; // tier 1
        feeTier[2] = _config[2]; // tier 2
        feeTierLimits[0] = _config[3]; // tier 1 listed
        feeTierLimits[1] = _config[4]; // tier 1 sent
        feeTierLimits[2] = _config[5]; // tier 2 listed
        feeTierLimits[3] = _config[6]; // tier 2 sent
    }

    /**
     * @dev Pull list funds.
     * @param _ID The list ID to pull from.
     * Note: Only List Owner or Admins can call this function.
     */
    function withdraw(uint256 _ID) external nonReentrant {
        if (!isListOwnerAdmin(_ID)) revert InvalidUser();
        uint256 releasable = sentValueTotal[_ID] - releasedValueTotal[_ID];
        uint256 fee = releasable * getFeePercentage(_ID) / 1000;
        uint256 payment = releasable - fee;
        require(payment != 0, "List is not due payment");
        releasedValueTotal[_ID] += releasable;
        vaultBalance += fee;
        (bool success, ) = payable(msg.sender).call{ value: payment } ("");
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

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
