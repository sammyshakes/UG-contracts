// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "./ERC1155/tokens/UGPackedBalance/UGMintBurnPackedBalance1.sol";
import "./ERC1155/utils/Ownable.sol";
import "./interfaces/IUGNFT.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract UGNFT is UGMintBurnPackedBalance, IUGNFT, Ownable {

  /*///////////////////////////////////////////////////////////////
                              TOKEN BASE  IDS
  //////////////////////////////////////////////////////////////*/

  uint16 constant RING = 5000;
  uint16 constant AMULET = 10000;
  uint16 constant FORGE = 15000;
  uint16 constant FIGHT_CLUB = 20000;

  uint128 constant RING_MAX_SUPPLY = 4000;
  uint128 constant AMULET_MAX_SUPPLY = 4000;
  uint128 constant FORGE_MAX_SUPPLY = 2000;
  uint128 constant FIGHT_CLUB_MAX_SUPPLY = 2000;

  /*///////////////////////////////////////////////////////////////
                                 NFT INDEXES
  //////////////////////////////////////////////////////////////*/  

   //user total balances bit indexes
  uint256 internal constant RING_INDEX  = 2;
  uint256 internal constant AMULET_INDEX  = 3;
  uint256 internal constant FORGE_INDEX  = 4;
  uint256 internal constant FIGHT_CLUB_INDEX  = 5;

  //maps id to packed fighter
  mapping(uint256 => ForgeFightClub) public idToForgeFightClub;
  mapping(uint256 => RingAmulet) public idToRingAmulet;

  uint256 public ttlRings;
  uint256 public ttlAmulets;
  uint256 public ttlFightClubs;
  uint256 public ttlForges;

  /*///////////////////////////////////////////////////////////////
                              PRIVATE VARIABLES
  //////////////////////////////////////////////////////////////*/
  mapping(address => bool) private _admins;
  string public baseURI;

  /*///////////////////////////////////////////////////////////////
                                EVENTS
   //////////////////////////////////////////////////////////////*/
  event LevelUpRingAmulet(uint256 indexed tokenId , uint256 indexed level, uint256 timestamp);
  event LevelUpForgeFightClub(uint256 indexed tokenId , uint256 timestamp, uint256 indexed level, uint256 indexed size);
  event RingAmuletMinted(uint256 indexed id, address indexed to, RingAmulet ringAmulet);
  event ForgeFightClubMinted(uint256 indexed id, address indexed to, ForgeFightClub ffc);
  event FightClubUnstakeTimeUpdated(uint256 tokenId, uint256 timestamp);

  /*///////////////////////////////////////////////////////////////
                                ERRORS
  //////////////////////////////////////////////////////////////*/
  error Unauthorized();
  error InvalidTokenID(uint256 tokenId);
  error MaxSupplyReached();

  string private _name;
  string private _symbol;

  // set the base URI
  constructor(string memory __uri, string memory __name, string memory __symbol)  {
    baseURI = __uri;
    _name = __name;
    _symbol = __symbol;
  }

  /*///////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function name() external view returns (string memory){
    return _name;
  }

  function symbol() external view returns (string memory){
    return _symbol;
  }

  function tokenURI(uint256 tokenId) external view returns (string memory){
    return this.uri(tokenId);
  }

  function getForgeFightClub(uint256 tokenId) external view returns (ForgeFightClub memory){
    return idToForgeFightClub[tokenId];
  }

  function getRingAmulet(uint256 tokenId) external view returns (RingAmulet memory) {
    return idToRingAmulet[tokenId];
  }

  function checkUserBatchBalance(address user, uint256[] calldata tokenIds) external view returns (bool){
    for (uint i = 0; i < tokenIds.length;i++){
      uint256 bal = balanceOf(user, tokenIds[i]);
      if(bal == 0) revert InvalidTokenID({tokenId: tokenIds[i]});
    }
    return true;
  }  

  function getNftIDsForUser(address user, uint nftIndex) external view returns (uint256[] memory){
    require(nftIndex > 1 || nftIndex <= 5, "Invalid Token Type");
    //which nft?
    uint prefix;
    uint ttlNfts;    
    if(nftIndex == RING_INDEX){
      prefix = RING;
      ttlNfts = ttlRings;
    }
    if(nftIndex == AMULET_INDEX){
      prefix = AMULET;
      ttlNfts = ttlAmulets;
    }
    if(nftIndex == FIGHT_CLUB_INDEX){
      prefix = FIGHT_CLUB;
      ttlNfts = ttlFightClubs;
    }
    if(nftIndex == FORGE_INDEX){
      prefix = FORGE;
      ttlNfts = ttlForges;
    }
    //get balance of nfts
    uint256 num = getValueInBin(userTotalBalances[user], USER_TOTAL_BALANCES_BITS_SIZE, nftIndex);
    uint256[] memory _tokenIds = new uint256[](num);
    //loop through user balances until we find all the rings
    uint count;
    for(uint i=1; count<num && i <= ttlNfts; i++){
      if(balanceOf(user, prefix + i) ==1){
        _tokenIds[count] = prefix + i;
        count++;
      }
    }
    return _tokenIds;
  }

  function getForgeFightClubs(uint256[] calldata tokenIds) external view returns (ForgeFightClub[] memory){
    ForgeFightClub[] memory ffc = new ForgeFightClub[](tokenIds.length);
    for (uint i = 0; i < tokenIds.length; i++) {
      ffc[i] = idToForgeFightClub[tokenIds[i]];
    }
    return ffc;
  }
  
  /*///////////////////////////////////////////////////////////////
                              WRITE FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  
  function mintRingAmulet(
    address _to, 
    uint256 _level, 
    bool isRing
  ) external onlyAdmin {    
    uint256 _id;
    if(isRing){
      if(ttlRings >= RING_MAX_SUPPLY) revert MaxSupplyReached();
      _id = ++ttlRings + RING;

      //update ring balance for user
      _updateIDUserTotalBalance(_to, RING_INDEX, 1, Operations.Add);
    } else {
      if(ttlAmulets >= AMULET_MAX_SUPPLY) revert MaxSupplyReached();
      _id = ++ttlAmulets + AMULET;
      //update amulet balance for user
      _updateIDUserTotalBalance(_to, AMULET_INDEX, 1, Operations.Add);
    }

    RingAmulet memory traits;
    traits.level = uint8(_level);
    traits.lastLevelUpgradeTime = uint32(block.timestamp);
    idToRingAmulet[_id] = traits;

    _mint( _to,  _id, 1,  "");
    emit RingAmuletMinted(_id, _to, traits);
  }

  function mintFightClubForge(
    address _to, 
    bytes memory _data, 
    uint256 _size, 
    uint256 _level, 
    bool isFightClub
  ) external onlyAdmin {
    uint256 _id;
    if(isFightClub){
      if(ttlFightClubs >= FIGHT_CLUB_MAX_SUPPLY) revert MaxSupplyReached();
      _id = ++ttlFightClubs + FIGHT_CLUB;
     
      //update fight club balance for user
      _updateIDUserTotalBalance(_to, FIGHT_CLUB_INDEX, 1, Operations.Add);

    } else {
      if(ttlForges >= FORGE_MAX_SUPPLY) revert MaxSupplyReached();
      _id = ++ttlForges + FORGE;
     
      //update forge balance for user
      _updateIDUserTotalBalance(_to, FORGE_INDEX, 1, Operations.Add);
    }

    ForgeFightClub memory traits;
    traits.size = uint8(_size);
    traits.level = uint8(_level);
    traits.id = uint16(_id);
    traits.lastLevelUpgradeTime = uint32(block.timestamp);
    traits.owner = _to;
    idToForgeFightClub[_id] = traits;

    _mint( _to,  _id, 1,  _data);
    emit ForgeFightClubMinted(_id, _to, traits);
  }

  function levelUpFightClubsForges(
    uint256[] calldata tokenIds, 
    uint256[] calldata newSizes, 
    uint256[] calldata newLevels
  ) external onlyAdmin returns (ForgeFightClub[] memory) {
    if(tokenIds.length != newLevels.length) revert MismatchArrays();
    if(tokenIds.length != newSizes.length) revert MismatchArrays();
    ForgeFightClub[] memory traits = new ForgeFightClub[](tokenIds.length);

    for(uint i =0; i<tokenIds.length;i++){
      traits[i] = idToForgeFightClub[tokenIds[i]];
      //0 means no change to trait     
      traits[i].size = (newSizes[i] != 0) ? uint8(newSizes[i]) : traits[i].size;       
      traits[i].level = (newLevels[i] != 0) ? uint8(newLevels[i]) : traits[i].level;
      traits[i].lastLevelUpgradeTime = uint32(block.timestamp);      
      
      idToForgeFightClub[tokenIds[i]] = traits[i];  
    
      emit LevelUpForgeFightClub(tokenIds[i], block.timestamp, traits[i].level, traits[i].size);
    }
    return traits;
  }

  function levelUpRingAmulets(
    uint256 tokenId, 
    uint256 newLevel
  ) external onlyAdmin {
    
    RingAmulet memory traits ;
    traits.level = uint8(newLevel);
    traits.lastLevelUpgradeTime = uint32(block.timestamp);
    idToRingAmulet[tokenId] = traits;
    
    emit LevelUpRingAmulet(tokenId, traits.level, block.timestamp);
  }

  function safeTransferFrom(
    address _from, 
    address _to, 
    uint256 _id, 
    uint256 _amount, 
    bytes memory _data
  ) public override (UGPackedBalance, IUGNFT){
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), " INVALID_OPERATOR");
    require(_to != address(0)," INVALID_RECIPIENT");
    
   
    if(_id > RING && _id <= RING + ttlRings) {
        _updateIDUserTotalBalance(_to, RING_INDEX, _amount, Operations.Add);
        _updateIDUserTotalBalance(_from, RING_INDEX, _amount, Operations.Sub);
      }
      if(_id > AMULET && _id <= AMULET + ttlAmulets){
        _updateIDUserTotalBalance(_to, AMULET_INDEX, _amount, Operations.Add);
        _updateIDUserTotalBalance(_from, AMULET_INDEX, _amount, Operations.Sub); 
      }
      if(_id > FIGHT_CLUB && _id <= FIGHT_CLUB + ttlFightClubs) {
        _updateIDUserTotalBalance(_to, FIGHT_CLUB_INDEX, _amount, Operations.Add); // Add amount to recipient
        _updateIDUserTotalBalance(_from, FIGHT_CLUB_INDEX, _amount, Operations.Sub); // Add amount to recipient
        idToForgeFightClub[_id].owner = _to;
      }
      if(_id > FORGE && _id <= FORGE + ttlForges) {
        _updateIDUserTotalBalance(_to, FORGE_INDEX, _amount, Operations.Add); // Add amount to recipient
        _updateIDUserTotalBalance(_from, FORGE_INDEX, _amount, Operations.Sub); // Add amount to recipient
        idToForgeFightClub[_id].owner = _to;
      }

    _safeTransferFrom(_from, _to, _id, _amount);
    _callonERC1155Received(_from, _to, _id, _amount, gasleft(), _data);
  }

  function safeBatchTransferFrom(
    address _from, 
    address _to, 
    uint256[] calldata _ids, 
    uint256[] calldata _amounts,
    bytes memory _data
  ) public override (UGPackedBalance, IUGNFT){
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), " INVALID_OPERATOR");
    require(_to != address(0)," INVALID_RECIPIENT");
    uint256 _index;
    

    for(uint i = 0; i < _ids.length; i++){
      if(_ids[i] > RING && _ids[i] <= RING + ttlRings){
        _index = RING_INDEX;
      } 
      if(_ids[i] > AMULET && _ids[i] <= AMULET + ttlAmulets) {
        _index = AMULET_INDEX;
      }
      if(_ids[i] > FIGHT_CLUB && _ids[i]<= FIGHT_CLUB + ttlFightClubs) {
        _index = FIGHT_CLUB_INDEX;
        idToForgeFightClub[_ids[i]].owner = _to;
      }
      if(_ids[i] > FORGE && _ids[i] <= FORGE + ttlForges) {
        _index = FORGE_INDEX;
        idToForgeFightClub[_ids[i]].owner = _to;
      }

      _updateIDUserTotalBalance(_to, _index, _amounts[i], Operations.Add);
      _updateIDUserTotalBalance(_from, _index, _amounts[i], Operations.Sub);  
    }

    _safeBatchTransferFrom(_from, _to, _ids, _amounts);
    _callonERC1155BatchReceived(_from, _to, _ids, _amounts, gasleft(), _data);
  }

  function uri(uint256 tokenId) external view returns (string memory) {
    string memory jsonString;
    string memory imageId;
    string memory _uri;

    //if ring
    if(tokenId > RING && tokenId <= RING + ttlRings) {
      RingAmulet memory traits = idToRingAmulet[tokenId];
      if (traits.lastLevelUpgradeTime != 0) {
        jsonString = string(abi.encodePacked(
        jsonString,
        Strings.toString(traits.level),',',
        Strings.toString(traits.lastLevelUpgradeTime)
        ));
      }

      _uri = string(abi.encodePacked(
        baseURI,
        "ring/ring.png",
        "?traits=",
        jsonString
      ));
    }

    //if amulet
    if(tokenId > AMULET && tokenId <= AMULET + ttlAmulets) {
      RingAmulet memory traits = idToRingAmulet[tokenId];
      if (traits.lastLevelUpgradeTime != 0) {
        jsonString = string(abi.encodePacked(
        jsonString,
        Strings.toString(traits.level),',',
        Strings.toString(traits.lastLevelUpgradeTime)
        ));
      }

      _uri = string(abi.encodePacked(
        baseURI,
        "amulet/amulet.png",
        "?traits=",
        jsonString
      ));
    }

    //if forge or fight club
    if( (tokenId > FORGE && tokenId <= FORGE + ttlForges) ||
        (tokenId > FIGHT_CLUB && tokenId <= FIGHT_CLUB + ttlFightClubs) ){
      //get forge / fight club
      ForgeFightClub memory traits = idToForgeFightClub[tokenId];
      //if Fight Club
      if(tokenId > FIGHT_CLUB && tokenId <= FIGHT_CLUB + ttlFightClubs){
        //using imageId as a holder variable for url segment
        imageId = string(abi.encodePacked('fightclub/',Strings.toString(tokenId))) ;//replace with fight club image id
      }
      //if forge
      if(tokenId > FORGE && tokenId <= FORGE + ttlForges){
        //using imageId as a holder variable for url segment
        imageId = string(abi.encodePacked('forge/',Strings.toString(traits.size))) ;//replace with fight club image id
      }

      if (traits.lastLevelUpgradeTime != 0) {
        jsonString = string(abi.encodePacked(
        jsonString,
        Strings.toString(traits.id),',',
        Strings.toString(traits.level),',',
        Strings.toString(traits.size),',',
        Strings.toString(traits.lastLevelUpgradeTime),',',
        Strings.toString(traits.lastUnstakeTime)
        ));
      }

      _uri = string(abi.encodePacked(
        baseURI,
        imageId,
        ".png",
        "?traits=",
        jsonString
      ));
    } 

    return _uri;
  }

  // RING_INDEX  = 2;
  // AMULET_INDEX  = 3;
  // FORGE_INDEX  = 4;
  // FIGHT_CLUB_INDEX  = 5;
  function burn(address _from, uint256 _id, uint256 _index) external onlyAdmin {
    
    _updateIDUserTotalBalance(_from, _index, 1, Operations.Sub); // Add amount to recipient
    
     _burn( _from,  _id,  1);
  }

  function batchBurn(address _from, uint256[] memory _ids, uint256[] memory amounts, uint256 _index) external onlyAdmin {
    require(_ids.length == amounts.length, "Mismatch Arrays");
    
    _updateIDUserTotalBalance(_from, _index, _ids.length, Operations.Sub); // Add amount to recipient
    
     _batchBurn( _from,  _ids, amounts );
  }

  /*///////////////////////////////////////////////////////////////
                    ONLY ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  function setForgeFightClub(uint256 tokenId, ForgeFightClub memory _ffc) external onlyAdmin{
    idToForgeFightClub[tokenId] = _ffc;
  }

  function setFightClubUnstakeTime (uint256 tokenId, bool isUnstaking) external onlyAdmin {
    idToForgeFightClub[tokenId].lastUnstakeTime = isUnstaking ? uint32(block.timestamp) : 0;
    emit FightClubUnstakeTimeUpdated(tokenId, block.timestamp);
  }  

  function setRingAmulet(uint256 tokenId, RingAmulet memory _ra) external onlyAdmin {
    idToRingAmulet[tokenId] = _ra;
  }
  /*///////////////////////////////////////////////////////////////
                    CONTRACT MANAGEMENT OPERATIONS
  //////////////////////////////////////////////////////////////*/


  modifier onlyAdmin() {
    if(!_admins[msg.sender]) revert Unauthorized();
    _;
  }

   function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setBaseURI(string calldata __uri) external onlyOwner {
    baseURI = __uri;
  }

  /*///////////////////////////////////////////////////////////////
                       ERC165 FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Query if a contract implements an interface
   * @param _interfaceID  The interface identifier, as specified in ERC-165
   * @return `true` if the contract implements `_interfaceID` and
   */
  function supportsInterface(bytes4 _interfaceID) public override(UGPackedBalance) virtual pure returns (bool) {
    if (_interfaceID == 0xd9b67a26 ||
        _interfaceID == 0x0e89341c) {
      return true;
    }
    return super.supportsInterface(_interfaceID);
  }

  //////////////////////////////////////
  //      Unsupported Functions       //
  /////////////////////////////////////

  fallback () external {
    revert("UGNFT: INVALID_METHOD");
  }
}
