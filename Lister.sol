// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.23;

import {Admins} from "./Admins.sol";

/// @author developer's github https://github.com/HalfSuperNate
contract Lister is Admins{
    mapping(uint256 => address[]) public listID;
    mapping(address => mapping(uint256 => bool)) public listed;
    mapping(address => mapping(uint256 => uint256)) public sentValue;
    mapping(uint256 => bool) public trackValue;
    mapping(uint256 => bool) public isActiveList;
    mapping(uint256 => uint256) public cost;
    mapping(uint256 => uint256) public limit;
    mapping(uint256 => uint256[2]) public timer;
    uint256 public featuredList;
    address public vault;

    error AlreadyListed();
    error Closed();
    error NotListed();
    error TimeEnded();
    error TimeNotStarted();
    error ValueRequired();
    
    constructor() Admins(msg.sender) {
        vault = msg.sender;
    }

    /**
     * @dev User can get a list of addresses on the specified list.
     */
    function getList(uint256 _ID) external view returns(address[] memory) {
        return listID[_ID];
    }

    /**
     * @dev User can get a list of values sent on the specified list if tracked.
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
     */
    function getSentTotal(uint256 _ID) external view returns(uint256) {
        uint256 _total;
        uint256[] memory _values = getSentValues(_ID);
        for (uint256 i = 0; i < _values.length; i++) {
            _total += _values[i];
        }
        return _total;
    }

    /**
     * @dev Admin can set if a list is active to collect.
     * @param _ID The list ID to edit.
     * @param _cost Cost for getting listed.
     */
    function setListCost(uint256 _ID, uint256 _cost) public onlyAdmins {
        cost[_ID] = _cost;
    }

    /**
     * @dev Admin can set if a list has a limit.
     * @param _ID The list ID to edit.
     * @param _limit Limit at 0 is limitless, otherwise limited at limit.
     */
    function setListLimit(uint256 _ID, uint256 _limit) public onlyAdmins {
        limit[_ID] = _limit;
    }

    /**
     * @dev Admin can set if a list has a start and stop time.
     * @param _ID The list ID to edit.
     * @param _StartEndTime 0 ignores timer, otherwise start at time[0] stop at time[1].
     */
    function setListTimer(uint256 _ID, uint256[2] calldata _StartEndTime) public onlyAdmins {
        timer[_ID] = _StartEndTime;
    }

    /**
     * @dev Admin can set if a list is active & set if a list is tracking value sent.
     * @param _ID The list ID to edit.
     * @param _state Flag true for active false for closed.
     * @param _trackState Flag true for tracking false for not.
     */
    function setListState(uint256 _ID, bool _state, bool _trackState) public onlyAdmins {
        isActiveList[_ID] = _state;
        setTrackValueState(_ID, _trackState);
    }

    /**
     * @dev Admin can set if a list is tracking value sent.
     * @param _ID The list ID to edit.
     * @param _state Flag true for tracking false for not.
     */
    function setTrackValueState(uint256 _ID, bool _state) public onlyAdmins {
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
     * @dev Admin can list a user on a specified list.
     * @param _ID The list ID to get listed on.
     */
    function listSpecified(uint256 _ID, address _user) public onlyAdmins {
        if (listed[_user][_ID]) revert AlreadyListed();
        if (limit[_ID] != 0 && listID[_ID].length >= limit[_ID]) revert Closed();
        listed[_user][_ID] = true;
        listID[_ID].push(_user);
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
     * @dev Allow admins to set a new vault address.
     * @param _newVault New vault to set.
     */
    function setVault(address _newVault) public onlyAdmins {
        require(vault != address(0), "Vault Cannot Be 0");
        vault = _newVault;
    }

    /**
     * @dev Pull funds to the vault address.
     */
    function withdraw() external {
        require(vault != address(0), "Vault Cannot Be 0");
        (bool success, ) = payable(vault).call{ value: address(this).balance } ("");
        require(success);
    }
}
