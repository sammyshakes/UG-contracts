// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

interface IUBlood {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function updateOriginAccess() external;
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
    function addAdmin(address addr) external ;//onlyOwner 
    function removeAdmin(address addr) external ;//onlyOwner 
    function balanceOf(address account) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}