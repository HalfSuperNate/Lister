// SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.23;

import {Admins} from "./Admins.sol";

/// @author developer's github https://github.com/HalfSuperNate
contract Lister is Admins{
    mapping(uint256 => address[]) public listID;
    mapping(address => mapping(uint256 => bool)) public listed;
    mapping(uint256 => bool) public isActiveList;
    mapping(uint256 => uint256) public cost;
    uint256 public featuredList;
    address public vault;

    error AlreadyListed();
    error ListClosed();
    error ListCostRequired();

    constructor() Admins(msg.sender) {
        vault = msg.sender;
    }

    /**
     * @dev Admin can set if a list is active to collect.
     * @param _ID The list ID to edit.
     * @param _cost Flag true for active false for closed.
     */
    function setListCost(uint256 _ID, uint256 _cost) public onlyAdmins {
        cost[_ID] = _cost;
    }

    /**
     * @dev Admin can set if a list is active to collect.
     * @param _ID The list ID to edit.
     * @param _state Flag true for active false for closed.
     */
    function setListState(uint256 _ID, bool _state) public onlyAdmins {
        isActiveList[_ID] = _state;
    }

    /**
     * @dev Admin can set a featured list.
     * @param _ID The list ID.
     */
    function setFeaturedList(uint256 _ID) public onlyAdmins {
        featuredList = _ID;
    }

    /**
     * @dev User can get listed on a specified list.
     * @param _ID The list ID to get listed on.
     */
    function listMeSpecified(uint256 _ID) public payable {
        if (listed[msg.sender][_ID]) revert AlreadyListed();
        if (!isActiveList[_ID]) revert ListClosed();
        if (msg.value < cost[_ID]) revert ListCostRequired();
        listed[msg.sender][_ID] = true;
        listID[_ID].push(msg.sender);
    }

    /**
     * @dev User can get listed on the featured list.
     */
    function listMe() external {
        listMeSpecified(featuredList);
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