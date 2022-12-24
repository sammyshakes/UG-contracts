// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "./ERC1155/tokens/UGPackedBalance/UGMintBurnPackedBalance1.sol";
import "./ERC1155/utils/Ownable.sol";
import "./interfaces/IUGFYakuza.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface iUGRaid {

  struct RaidEntryTicket {
    uint8 sizeTier;
    uint8 fighterLevel;
    uint8 yakuzaFamily;
    uint8 courage;
    uint8 brutality;
    uint8 cunning;
    uint8 knuckles;
    uint8 chains;
    uint8 butterfly;
    uint8 machete;
    uint8 katana;
    uint16 scars;
    uint32 sweat;
    uint32 fighterId;
    uint32 entryFee;
    uint32 winnings;
  }
}

contract UGFYakuza is UGMintBurnPackedBalance, IUGFYakuza, Ownable {

  /*///////////////////////////////////////////////////////////////
                                 FIGHTERS
  //////////////////////////////////////////////////////////////*/  

  //user total balances bit index
  uint32 constant FIGHTER = 0;
  uint256 constant FIGHTER_INDEX  = 1;
  uint256 public ttlFYakuzas;
  uint256 public ttlFYakuzasBurned;
  //maps id to packed fighter
  mapping(uint256 => uint256) public idToFYakuza;  
  // Mapping from owner to list of owned token IDs
  mapping(address => mapping(uint256 => uint256)) private _ownedTokens;  
  // Mapping from token ID to index of the owner tokens list
  mapping(uint256 => uint256) private _ownedTokensIndex; 
  mapping(address => bool) private _admins; 

  /*///////////////////////////////////////////////////////////////
                                EVENTS
   //////////////////////////////////////////////////////////////*/
  event LevelUpFighter(uint256 indexed tokenId , uint256 indexed level, uint256 timestamp);
  event FighterYakuzaMigrated(uint256 indexed id, address indexed to, FighterYakuza fighter);
  event RaidTraitsUpdated(uint256 indexed fighterId, FighterYakuza fighter);
  event FighterUpdated(uint256 indexed tokenId, FighterYakuza fighter); 

  /*///////////////////////////////////////////////////////////////
                                ERRORS
  //////////////////////////////////////////////////////////////*/
  error Unauthorized();
  error InvalidTokenID(uint256 tokenId);
  error MaxSupplyReached();

  /*///////////////////////////////////////////////////////////////
                    CONTRACT MANAGEMENT OPERATIONS
  //////////////////////////////////////////////////////////////*/
  string private _name;
  string private _symbol;  
  string public baseURI;
  constructor(string memory _uri, string memory __name, string memory __symbol)  {
    baseURI = _uri;
    _name = __name;
    _symbol = __symbol;
  }

  modifier onlyAdmin() {
    if(!_admins[msg.sender]) revert Unauthorized();
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function totalSupply() public view virtual returns (uint256) {
    return ttlFYakuzas - ttlFYakuzasBurned;
  }  

  function getNumFightersForUser(address user) external view returns (uint256) {
    return getValueInBin(userTotalBalances[user], USER_TOTAL_BALANCES_BITS_SIZE, FIGHTER_INDEX);
  }

  function getFighters(uint256[] calldata tokenIds) external view returns (FighterYakuza[] memory){
    FighterYakuza[] memory FY = new FighterYakuza[](tokenIds.length);
    for (uint i = 0; i < tokenIds.length; i++) {
      FY[i] = unPackFighter(idToFYakuza[tokenIds[i]]);
    }
    return FY;
  }

  function getFighter(uint256 tokenId) external view returns (FighterYakuza memory){   
    return unPackFighter(idToFYakuza[tokenId]);    
  }

  function checkUserBatchBalance(address user, uint256[] calldata tokenIds) external view returns (bool){
    for (uint i = 0; i < tokenIds.length;i++){
      uint256 bal = balanceOf(user, tokenIds[i]);
      if(bal == 0) revert InvalidTokenID({tokenId: tokenIds[i]});
    }
    return true;
  }

  function balanceOf(address _owner) public view returns (uint256){
    return _balanceOf(_owner);
  }
  
  function name() external view returns (string memory){
    return _name;
  }

  function symbol() external view returns (string memory){
    return _symbol;
  }

  function uri(uint256 tokenId) external view returns (string memory) {
    return this.tokenURI(tokenId);
  }
   
  /*///////////////////////////////////////////////////////////////
                    FIGHTER MIGRATION
  //////////////////////////////////////////////////////////////*/
  function batchMigrateFYakuza(
    address _to, 
    uint256[] calldata v1TokenIds,
    FighterYakuza[] calldata oldFighters
  ) external  onlyAdmin {     
    if(v1TokenIds.length != oldFighters.length) revert MismatchArrays();

    uint256[] memory _ids = new uint256[](oldFighters.length);
    uint256[] memory _amounts = new uint256[](oldFighters.length);
    uint256 firstMintId = ttlFYakuzas + 1;
    // vars for packing
    uint256 newFighter;
    uint256 nextVal;
    for(uint i; i<oldFighters.length;i++){
      _ids[i] =  FIGHTER  + firstMintId++ ;
      _amounts[i] = 1;
        
      newFighter = oldFighters[i].isFighter ? 1 : 0;
      nextVal = 0;//setting all gen variables to 0
      newFighter |= nextVal<<1;
      nextVal = oldFighters[i].level;
      newFighter |= nextVal<<2;
      nextVal = oldFighters[i].isFighter ? 0 : oldFighters[i].rank;
      newFighter |= nextVal<<10;
      nextVal = oldFighters[i].courage;
      newFighter |= nextVal<<18;
      nextVal =  oldFighters[i].cunning;
      newFighter |= nextVal<<26;
      nextVal =  oldFighters[i].brutality;
      newFighter |= nextVal<<34;
      nextVal =  oldFighters[i].knuckles;
      newFighter |= nextVal<<42;
      nextVal =  oldFighters[i].chains;
      newFighter |= nextVal<<50;
      nextVal =  oldFighters[i].butterfly;
      newFighter |= nextVal<<58;
      nextVal =  oldFighters[i].machete;
      newFighter |= nextVal<<66;
      nextVal =  oldFighters[i].katana;
      newFighter |= nextVal<<74;
      nextVal =  oldFighters[i].Gen == 1 ? 0 : 100;
      newFighter |= nextVal<<90;
      //image id
      nextVal = v1TokenIds[i];
      newFighter |= nextVal<<106;
      //lastLevelUpgrade
      nextVal = block.timestamp;
      newFighter |= nextVal<<138;
      //lastRankUpgrade
      nextVal = block.timestamp;
      newFighter |= nextVal<<170;
      //lastRaidTime
      nextVal = block.timestamp;
      newFighter |= nextVal<<202;

      //add to array for first time (derived imageId from original v1 fighter)
      idToFYakuza[_ids[i]] = newFighter;

      emit FighterYakuzaMigrated(_ids[i], _to, unPackFighter(newFighter));
    }
    _addToOwnerTokenList(_to, _ids);
    //update total fighter yakuzas
    ttlFYakuzas += oldFighters.length;
    //update fighter balance for user
    _updateIDUserTotalBalance(_to, FIGHTER_INDEX, v1TokenIds.length, Operations.Add); // Add amount to recipient
    _batchMint( _to,  _ids, _amounts, "");
  }   

  function levelUpFighters(uint256[] calldata tokenIds, uint256[] calldata levels) external onlyAdmin {
    if(tokenIds.length != levels.length) revert MismatchArrays();

    FighterYakuza memory fy;
    for(uint i =0; i<tokenIds.length;i++){
      fy = unPackFighter(idToFYakuza[tokenIds[i]]);
      if(fy.isFighter){
        fy.level = uint8(levels[i]);
        fy.lastLevelUpgradeTime = uint32(block.timestamp);
        idToFYakuza[tokenIds[i]] = packFighter(fy);
        emit LevelUpFighter(tokenIds[i], fy.level, block.timestamp);
      }
    }
  }

  function setRaidTraitsFromPacked(uint256[] memory packedTickets) external onlyAdmin {
    iUGRaid.RaidEntryTicket memory ticket;
    FighterYakuza memory FY;
    for(uint i =0; i<packedTickets.length;i++){
      ticket = unpackTicket(packedTickets[i]);
      
      if(ticket.fighterId > FIGHTER + ttlFYakuzas ||
        ticket.fighterId <= FIGHTER) revert InvalidTokenID({tokenId: ticket.fighterId});

      FY = unPackFighter(idToFYakuza[ticket.fighterId]);
      FY.brutality = ticket.brutality;
      FY.courage = ticket.courage;
      FY.cunning = ticket.cunning;
      FY.scars = ticket.scars;
      FY.knuckles = ticket.knuckles;
      FY.chains = ticket.chains;
      FY.butterfly = ticket.butterfly;
      FY.machete = ticket.machete;
      FY.katana = ticket.katana;
      FY.lastRaidTime = uint32(block.timestamp);
      //broken weapons scores will have modulo 10 (%10) = 1
      idToFYakuza[ticket.fighterId] = packFighter(FY);

      emit RaidTraitsUpdated(ticket.fighterId, FY);
    }
  }

  function setFighter( uint256 tokenId, FighterYakuza memory FY) external onlyAdmin {
    idToFYakuza[tokenId] = packFighter(FY);
    emit FighterUpdated(tokenId, FY);
  }

  function getPackedFighters(uint256[] calldata tokenIds) external view returns (uint256[] memory){
    uint256[] memory _packedFighters = new uint256[](tokenIds.length);
    for (uint i = 0; i < tokenIds.length; i++) {
      if(tokenIds[i] > FIGHTER + ttlFYakuzas || tokenIds[i] <= FIGHTER) revert InvalidTokenID({tokenId: tokenIds[i]});
      _packedFighters[i] = idToFYakuza[tokenIds[i]];
    }
    return _packedFighters;
  }

  function burn(address _from, uint256 _id) external onlyAdmin {
    uint256[] memory ids = new uint256[](1);
    ids[0] = _id;
    _removeFromOwnerTokenList( _from, ids);
    _updateIDUserTotalBalance(_from, FIGHTER_INDEX, 1, Operations.Sub); // Add amount to recipient
    ttlFYakuzasBurned ++;
     _burn( _from,  _id,  1);
  }

  function batchBurn(address _from, uint256[] memory _ids, uint256[] memory amounts) external onlyAdmin {
    require(_ids.length == amounts.length, "Mismatch Arrays");
    _removeFromOwnerTokenList( _from, _ids);
    _updateIDUserTotalBalance(_from, FIGHTER_INDEX, _ids.length, Operations.Sub); // Add amount to recipient
    ttlFYakuzasBurned += _ids.length;
     _batchBurn( _from,  _ids, amounts );
  }

  function safeTransferFrom(
    address _from, 
    address _to, 
    uint256 _id, 
    uint256 _amount, 
    bytes memory _data
  ) public override {
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), " INVALID_OPERATOR");
    require(_to != address(0)," INVALID_RECIPIENT");
    uint256[] memory _ids = new uint256[](1);
    _ids[0] = _id;

    _removeFromOwnerTokenList( _from, _ids);
    _addToOwnerTokenList( _to, _ids);
    
    _updateIDUserTotalBalance(_to, FIGHTER_INDEX, _amount, Operations.Add); // Add amount to recipient
    _updateIDUserTotalBalance(_from, FIGHTER_INDEX, _amount, Operations.Sub); // Add amount to recipient
    
    _safeTransferFrom(_from, _to, _id, _amount);
    _callonERC1155Received(_from, _to, _id, _amount, gasleft(), _data);
  }

  function safeBatchTransferFrom(
    address _from, 
    address _to, 
    uint256[] calldata _ids, 
    uint256[] calldata _amounts,
    bytes memory _data
  ) public override (UGPackedBalance, IUGFYakuza){
    require((msg.sender == _from) || isApprovedForAll(_from, msg.sender), " INVALID_OPERATOR");
    require(_to != address(0)," INVALID_RECIPIENT");
    uint256 _index;

    _removeFromOwnerTokenList( _from, _ids);
    _addToOwnerTokenList( _to, _ids);

    for(uint i = 0; i < _ids.length; i++){
    
      if(_ids[i] > FIGHTER && _ids[i] <= FIGHTER + ttlFYakuzas) _index = FIGHTER_INDEX;

      _updateIDUserTotalBalance(_to, _index, _amounts[i], Operations.Add);
      _updateIDUserTotalBalance(_from, _index, _amounts[i], Operations.Sub);  
    }

    _safeBatchTransferFrom(_from, _to, _ids, _amounts);
    _callonERC1155BatchReceived(_from, _to, _ids, _amounts, gasleft(), _data);
  }

  function tokenURI(uint256 tokenId) external view returns (string memory) {
    string memory jsonString;
    string memory fyakuza;
    string memory imageId;
    string memory _uri;
    
      if(tokenId > FIGHTER && tokenId <= FIGHTER + ttlFYakuzas) {
        FighterYakuza memory traits = unPackFighter(idToFYakuza[tokenId]);
        if (traits.imageId != 0) {
          imageId = Strings.toString(traits.imageId);
          jsonString = string(abi.encodePacked(
          jsonString,
          Strings.toString(tokenId),',',
          Strings.toString((traits.isFighter)? 1 : 0),',',
          Strings.toString(traits.Gen),',',
          Strings.toString(traits.cunning),',',
          Strings.toString(traits.brutality),','
          ));

          jsonString = string(abi.encodePacked(
          jsonString,
          Strings.toString(traits.courage),',',
          Strings.toString(traits.level),',',
          Strings.toString(traits.lastLevelUpgradeTime),',',
          Strings.toString(traits.rank),',',
          Strings.toString(traits.lastRaidTime),','
          ));

          jsonString = string(abi.encodePacked(
          jsonString,
          Strings.toString(traits.scars),',',
          Strings.toString(traits.knuckles),',',
          Strings.toString(traits.chains),',',
          Strings.toString(traits.butterfly),',',
          Strings.toString(traits.machete),',',
          Strings.toString(traits.katana)
          ));
        }

        fyakuza = traits.isFighter ? "fighteryakuza/fighter/" : "fighteryakuza/yakuza/";

        _uri = string(abi.encodePacked(
          baseURI,
          fyakuza,
          imageId,
          ".png",
          "?traits=",
          jsonString
        ));
      }
    return _uri;
  }

   function unPackFighter(uint256 packedFighter) private pure returns (FighterYakuza memory) {
    FighterYakuza memory fighter;   
    fighter.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
    fighter.Gen = uint8(packedFighter>>1)%2 ;
    fighter.level = uint8(packedFighter>>2);
    fighter.rank = uint8(packedFighter>>10);
    fighter.courage = uint8(packedFighter>>18);
    fighter.cunning = uint8(packedFighter>>26);
    fighter.brutality = uint8(packedFighter>>34);
    fighter.knuckles = uint8(packedFighter>>42);
    fighter.chains = uint8(packedFighter>>50);
    fighter.butterfly = uint8(packedFighter>>58);
    fighter.machete = uint8(packedFighter>>66);
    fighter.katana = uint8(packedFighter>>74);
    fighter.scars = uint16(packedFighter>>90);
    fighter.imageId = uint16(packedFighter>>106);
    fighter.lastLevelUpgradeTime = uint32(packedFighter>>138);
    fighter.lastRankUpgradeTime = uint32(packedFighter>>170);
    fighter.lastRaidTime = uint32(packedFighter>>202);
    return fighter;
  }

  function packFighter(FighterYakuza memory unPackedFighter) private pure returns (uint256 ){
    uint256 packedFighter = unPackedFighter.isFighter ? 1 : 0;
      uint256 nextVal = unPackedFighter.Gen;
      packedFighter |= nextVal<<1;
      nextVal = unPackedFighter.level;
      packedFighter |= nextVal<<2;
      nextVal = unPackedFighter.isFighter ? 0 : unPackedFighter.rank;
      packedFighter |= nextVal<<10;
      nextVal = unPackedFighter.courage;
      packedFighter |= nextVal<<18;
      nextVal =  unPackedFighter.cunning;
      packedFighter |= nextVal<<26;
      nextVal =  unPackedFighter.brutality;
      packedFighter |= nextVal<<34;
      nextVal =  unPackedFighter.knuckles;
      packedFighter |= nextVal<<42;
      nextVal =  unPackedFighter.chains;
      packedFighter |= nextVal<<50;
      nextVal =  unPackedFighter.butterfly;
      packedFighter |= nextVal<<58;
      nextVal =  unPackedFighter.machete;
      packedFighter |= nextVal<<66;
      nextVal =  unPackedFighter.katana;
      packedFighter |= nextVal<<74;
      nextVal =  unPackedFighter.scars;
      packedFighter |= nextVal<<90;
      //image id
      nextVal = unPackedFighter.imageId;
      packedFighter |= nextVal<<106;
      //lastLevelUpgrade
      nextVal = unPackedFighter.lastLevelUpgradeTime;
      packedFighter |= nextVal<<138;
      //lastRankUpgrade
      nextVal = unPackedFighter.lastRankUpgradeTime;
      packedFighter |= nextVal<<170;
      //lastRaidTime
      nextVal = unPackedFighter.lastRaidTime;
      packedFighter |= nextVal<<202;
      return packedFighter;
  }

   function unpackTicket(uint256 packedTicket) 
    private pure returns (iUGRaid.RaidEntryTicket memory _ticket)
  {
      _ticket.sizeTier = uint8(packedTicket);
      _ticket.fighterLevel = uint8(packedTicket>>8);
      _ticket.yakuzaFamily = uint8(packedTicket>>16);
      _ticket.courage = uint8(packedTicket>>24);
      _ticket.brutality = uint8(packedTicket>>32);
      _ticket.cunning = uint8(packedTicket>>40);
      _ticket.knuckles = uint8(packedTicket>>48);
      _ticket.chains = uint8(packedTicket>>56);
      _ticket.butterfly = uint8(packedTicket>>64);
      _ticket.machete = uint8(packedTicket>>72);
      _ticket.katana = uint8(packedTicket>>80);
      _ticket.scars = uint16(packedTicket>>96);
      _ticket.sweat = uint32(packedTicket>>128);
      _ticket.fighterId = uint32(packedTicket>>160);
      _ticket.entryFee = uint32(packedTicket>>192);
      return _ticket;
  }

  /*///////////////////////////////////////////////////////////////
                       ONLY OWNER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setBaseURI(string calldata _uri) external onlyOwner {
    baseURI = _uri;
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
    revert("UGFYakuza: INVALID_METHOD");
  }
}
