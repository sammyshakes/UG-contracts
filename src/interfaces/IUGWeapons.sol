 // SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

interface IUGWeapons {
 
    
    //weapons scores used to identify "metal"
    // steel = 10, bronze = 20, gold = 30, platinum = 50 , titanium = 80, diamond = 100
    function getTotalSupply(uint256 tokenId) external view returns (uint256);
    function balanceOf(address _owner, uint256 _id) external view returns (uint256);
    function mint(address _from, uint256 _id, uint256 _amount, bytes memory data) external;
    function batchMint(address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) external;
    function burn(address _from, uint256 _id, uint256 _amount) external;
    function batchBurn(address _to, uint256[] memory _ids, uint256[] memory _amounts) external;
   

    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
    function setRevealedBaseURI(string calldata uri) external;//onlyOwner
    //function tokenURIs(uint256 tokenId) external view returns (string memory) ;
    function addAdmin(address) external; // onlyOwner 
    function removeAdmin(address) external; // onlyOwner
  
}