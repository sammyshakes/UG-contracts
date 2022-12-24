 // SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

interface IUGNFT {

    struct ForgeFightClub {
        uint8 size;
        uint8 level;
        uint16 id;
        uint32 lastLevelUpgradeTime;
        uint32 lastUnstakeTime;
        address owner;
    }

    struct RingAmulet {
        uint8 level;
        uint32 lastLevelUpgradeTime;
    }
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
    function setBaseURI(string calldata uri) external;//onlyOwner
    function uri(uint256 tokenId) external view returns (string memory) ;
    function mintRingAmulet(address, uint256, bool ) external;//onlyAdmin  
    function mintFightClubForge(address _to, bytes memory _data, uint256 _size, uint256 _level, bool isFightClub) external;//onlyAdmin
    function checkUserBatchBalance(address user, uint256[] calldata tokenIds) external view returns (bool);
    function getNftIDsForUser(address , uint) external view returns (uint256[] memory);
    function getRingAmulet(uint256 ) external view returns (RingAmulet memory);
    function getForgeFightClub(uint256 tokenId) external view returns (ForgeFightClub memory);
    function getForgeFightClubs(uint256[] calldata tokenIds) external view returns (ForgeFightClub[] memory); 
    function levelUpRingAmulets(uint256, uint256 ) external;
    function levelUpFightClubsForges(uint256[] calldata tokenIds, uint256[] calldata newSizes, uint256[] calldata newLevels) external returns (ForgeFightClub[] memory); // onlyAdmin
    function addAdmin(address) external; // onlyOwner 
    function removeAdmin(address) external; // onlyOwner
    function ttlFightClubs() external view returns (uint256);
    function ttlRings() external view returns (uint256);
    function ttlAmulets() external view returns (uint256);
    function ttlForges() external view returns (uint256);
    function setFightClubUnstakeTime (uint256 , bool) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}