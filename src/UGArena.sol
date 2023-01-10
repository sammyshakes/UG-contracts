// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGYakDen.sol";
import "./interfaces/IRandomizer.sol";
import "./interfaces/IUGgame.sol";
import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract UGArena is IUGArena, Ownable, ReentrancyGuard, Pausable {

  /** CONTRACTS */
  IRandomizer public randomizer;
  IUGNFT public ugNFT;
  IUGFYakuza public ugFYakuza;
  IUBlood public uBlood;
  IERC1155 public ierc1155;
  IERC1155 public ierc1155FY;
  IUGgame public ugGame;
  IUGYakDen public ugYakDen;

  //////////////////////////////////
  //          ERRORS             //
  /////////////////////////////////
  error InvalidTokens(uint256 tokenId);
  error InvalidToken();
  error AlreadyStaked();
  error NothingStaked();
  error MaximumAllowedActiveAmulets(uint256 tokenId);
  error MaximumAllowedActiveRings(uint256 tokenId);
  error MismatchArrays();
  error OnlyEOA(address txorigin, address sender);
  error InvalidOwner();
  error StakingCoolDown();

  //////////////////////////////////
  //          EVENTS             //
  /////////////////////////////////
  event TokenStaked(address indexed owner, uint256 indexed tokenId);
  event TokenUnStaked(address indexed owner, uint256 indexed tokenId);
  event TokensStaked(address indexed owner, uint256[] tokenIds, uint256 timestamp);
  event TokensClaimed(address indexed owner, uint256[] indexed tokenIds, bool unstaked, uint256 earned, uint256 timestamp);
  event BloodStolen(address indexed owner, uint256 indexed tokenId, uint256 indexed amount);
  event YakuzaTaxPaid(uint256 indexed amount);
  // Operations for _updateIDBalance
  enum Operations { Add, Sub }

  //Daily Blood Rate
  uint256 private DAILY_BLOOD_RATE_PER_LEVEL = 100;
  //Daily Blood per Level
  uint256 private RING_DAILY_BLOOD_PER_LEVEL = 10;
  // fighters & yakuza must be staked for minimum days before they can be unstaked
  uint256 private MINIMUM_DAYS_TO_EXIT = 1 days;
  // yakuza take a 20% tax on all $BLOOD claimed
  uint256 private YAKUZA_TAX_PERCENTAGE = 20;
  // amount of $BLOOD earned so far
  uint256 public totalBloodEarned;
  

  uint16 constant RING = 5000;
  uint16 constant AMULET = 10000;

  // Constants regarding bin sizes for balance packing
  uint256 internal constant IDS_BITS_SIZE   = 1;
  uint256 internal constant IDS_PER_UINT256 = 256 / IDS_BITS_SIZE; 
  uint256 internal constant USER_TOTAL_BALANCES_BITS_SIZE   = 32;
  //user total balances bit indexes
  uint256 internal constant FIGHTER_INDEX  = 0;
  uint256 internal UNSTAKE_COOLDOWN = 48 hours;  

  // total Fighters staked
  uint256 public totalFightersStaked;
  // total sum of Rings staked
  uint256 private _totalRingsStaked;
  // total sum of Amulets staked
  uint256 private _totalAmuletsStaked;
  // Token IDs balances ; balances[address][id] => balance (using array instead of mapping for efficiency)
  mapping (address => mapping(uint256 => uint256)) internal stakedBalances;
  // map user address to packed uint256
  mapping (address => uint256) internal userTotalBalances;
  
  
  // maps tokenId to Fighter
  mapping(uint256 => Stake) private _fighterArena;
  mapping(address => uint256) private _ownersOfStakedRings;
  mapping(address => uint256) private _ownersOfStakedAmulets;
  mapping(uint256 => uint256) private _ringAmuletUnstakeTimes;  
  
  // admins
  mapping(address => bool) private _admins;

  constructor(address _ugnft, address _ugFYakuza, address _blood, address _randomizer, address _ugyakden) {
    ugNFT = IUGNFT(_ugnft);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    ierc1155 = IERC1155(_ugnft);
    ierc1155FY = IERC1155(_ugFYakuza);
    uBlood = IUBlood(_blood);
    randomizer = IRandomizer(_randomizer);
    ugYakDen = IUGYakDen(_ugyakden);
  }

  modifier onlyAdmin() {
    require(_admins[_msgSender()], "Arena: Only admins can call this");
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function numUserStakedFighters(address user) external view returns (uint256){
    return getValueInBin(userTotalBalances[user], USER_TOTAL_BALANCES_BITS_SIZE, FIGHTER_INDEX);
  }

  function getStakedRingIDForUser(address user) external view returns (uint256){
    return _ownersOfStakedRings[user];
  }

  function getStakedAmuletIDForUser(address user) external view returns (uint256){
    return _ownersOfStakedAmulets[user];
  }

  function getStake(uint256 tokenId) external view returns (Stake memory) {
    return _fighterArena[tokenId];
  }

  function getStakeOwner(uint256 tokenId) external view returns (address) {
    return _fighterArena[tokenId].owner;
  }

  function getRingAmuletUnstakeTime(uint256 tokenId) external view returns (uint256) {
    return _ringAmuletUnstakeTimes[tokenId];
  }

  function stakedByOwner(address owner) external view returns (uint256[] memory) {
    uint256 ownerTokenCount = getValueInBin(userTotalBalances[owner], USER_TOTAL_BALANCES_BITS_SIZE, FIGHTER_INDEX);
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(owner, i);
    }
    return tokenIds;
  }

  function calculateStakingRewards(uint256 tokenId) external view returns (uint256 owed) {
    uint256[] memory _ids = new uint256[](1);
    _ids[0] = tokenId;
    Stake memory myStake = _fighterArena[tokenId];
    uint256[] memory fighters = ugFYakuza.getPackedFighters(_ids);
    (uint256 ringLevel, uint256 ringExpireTime, uint256 extraAmuletDays, uint256 amuletExpireTime) = getAmuletRingInfo(myStake.owner);
    return _calculateStakingRewards(tokenId, ringLevel, ringExpireTime, extraAmuletDays, amuletExpireTime, unPackFighter(fighters[0]));
  }

 function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256 owed) {
    Stake memory myStake = _fighterArena[tokenIds[0]];
    (uint256 ringLevel, uint256 ringExpireTime, uint256 extraAmuletDays, uint256 amuletExpireTime) = getAmuletRingInfo(myStake.owner);

    uint256[] memory fighters = ugFYakuza.getPackedFighters(tokenIds);
    for (uint256 i; i < tokenIds.length; i++) {
      owed += _calculateStakingRewards(tokenIds[i], ringLevel, ringExpireTime, extraAmuletDays, amuletExpireTime, unPackFighter(fighters[i]));
    }
    return owed;
  }

  function _calculateStakingRewards(
    uint256 tokenId, 
    uint256 ringLevel, 
    uint256 ringExpireTime, 
    uint256 extraAmuletDays, 
    uint256 amuletExpireTime,
    IUGFYakuza.FighterYakuza memory fighter
  ) private view returns (uint256 owed) {
    Stake memory myStake = _fighterArena[tokenId];
    // check to make sure id is staked or return 0
    if (myStake.owner == address(0x00)) return 0;

    uint256 fighterExpireTime;
    if (fighter.isFighter) { // Fighter
      //calculate fighter expire time
      fighterExpireTime = fighter.lastLevelUpgradeTime + 7 days + extraAmuletDays;
      //calculate Amulet expire time
      if(amuletExpireTime > 0 && fighterExpireTime > amuletExpireTime) fighterExpireTime = amuletExpireTime;
      //check if raid timer expired
      if(fighterExpireTime > fighter.lastRaidTime + 7 days) fighterExpireTime = fighter.lastRaidTime + 7 days;
      //compare to current timestamp
      if(fighterExpireTime > block.timestamp ) fighterExpireTime = block.timestamp;
      //calculate owed base earnings
      if(fighterExpireTime > myStake.stakeTimestamp) owed += (fighterExpireTime - myStake.stakeTimestamp) *fighter.level* DAILY_BLOOD_RATE_PER_LEVEL / 1 days;
      //calculate Ring expire time
      if(ringExpireTime >= fighterExpireTime) ringExpireTime = fighterExpireTime;
      //calculate owed from Ring earnings
      if(ringExpireTime >= myStake.stakeTimestamp) owed += (ringExpireTime - myStake.stakeTimestamp) * (fighter.level * (ringLevel * RING_DAILY_BLOOD_PER_LEVEL)) / 1 days;        
    }
    return (owed);
  }

  function getAmuletRingInfo(address user) public view returns(uint256 ringLevel, uint256 ringExpireTime, uint256 extrAmuletDays, uint256 amuletExpireTime){
    IUGNFT.RingAmulet memory stakedRing;
    IUGNFT.RingAmulet memory stakedAmulet;
    uint256 ring = _ownersOfStakedRings[user];
    uint256 amulet = _ownersOfStakedAmulets[user];
    
    if (ring > 0) {
      stakedRing = ugNFT.getRingAmulet(ring);
      ringLevel = stakedRing.level;
    
      // ring expire time
      if(stakedRing.lastLevelUpgradeTime + 7 days < block.timestamp){
        ringExpireTime = stakedRing.lastLevelUpgradeTime + 7 days;
      } else ringExpireTime = block.timestamp;
    } else {
      ringLevel = 0;
      ringExpireTime = 0;
    }
      
    if(amulet > 0) {
      stakedAmulet = ugNFT.getRingAmulet( amulet);
      extrAmuletDays = stakedAmulet.level * 1 days;
      //calculate extra amulet days
      if(block.timestamp > stakedAmulet.lastLevelUpgradeTime + 7 days){
        amuletExpireTime = stakedAmulet.lastLevelUpgradeTime + 7 days;
      } else amuletExpireTime = block.timestamp;
    } else {
      extrAmuletDays = 0;
      amuletExpireTime = 0;
    }
  }
  
  function verifyAllStakedByUser(address user, uint256[] calldata _tokenIds) external view returns (bool) {
    for(uint i; i < _tokenIds.length; i++){  
       if(_fighterArena[_tokenIds[i]].owner != user) return false;
    }
    return true;
  }

  /*///////////////////////////////////////////////////////////////
                    WRITE FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function stakeManyToArena(uint256[] calldata tokenIds) external whenNotPaused nonReentrant {
    //get batch balances to ensure rightful owner and are not already staked
    if(!ugFYakuza.checkUserBatchBalance(_msgSender(), tokenIds)) revert InvalidToken();//InvalidTokens({tokenId: tokenId});
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    uint256[] memory FY = ugFYakuza.getPackedFighters(tokenIds);
    IUGFYakuza.FighterYakuza memory fighter;
    Stake memory myStake;

    _addToOwnerStakedTokenList(_msgSender(), tokenIds);
    
    for (uint i = 0; i < tokenIds.length; i++) {   
      fighter = unPackFighter(FY[i]);      
      require(fighter.isFighter, "only stake Fighters");

      myStake.stakeTimestamp = uint32(block.timestamp);
      myStake.owner = _msgSender();              
      myStake.bloodPerRank = 0;
      _fighterArena[tokenIds[i]] = myStake;    
      
      _amounts[i] = 1; //set amounts array for batch transfer  

      _updateIDStakedBalance(_msgSender(),tokenIds[i], _amounts[i], Operations.Add);
    }

    totalFightersStaked += tokenIds.length;

    _updateIDUserTotalBalance(_msgSender(),FIGHTER_INDEX, tokenIds.length, Operations.Add); 
  
    ugFYakuza.safeBatchTransferFrom(_msgSender(), address(this), tokenIds, _amounts, "");
    emit TokensStaked(_msgSender(), tokenIds, block.timestamp);
  }

  function payRaidRevenueToYakuza(uint256 amount) external onlyAdmin {    
    _payYakuzaTax(amount);
  }
  
  function _payYakuzaTax(uint amount) private {
    //this needs to pay new yak staking contract
    ugYakDen.payRevenueToYakuza(amount);
    emit YakuzaTaxPaid(amount);
  }

  function claimManyFromArena(uint256[] calldata tokenIds, bool unstake) external whenNotPaused nonReentrant {
    require(tokenIds.length > 0, "Empty Array");
    // Fetch the owner so we can give that address the $BLOOD.
    // If the same address does not own all tokenIds this transaction will fail.
    // This is especially relevant when the Game contract calls this function as the _msgSender() - it should NOT get the $BLOOD ofc.
    address account = _fighterArena[tokenIds[0]].owner;
    // The _admins[] check allows the Game contract to claim at level upgrades
    // and raid contract when raiding.
    if(account != _msgSender() && !_admins[_msgSender()]) revert InvalidToken();
    //get ring amulet info
    (uint256 ringLevel, uint256 ringExpireTime, uint256 extraAmuletDays, uint256 amuletExpireTime) = getAmuletRingInfo(account);   
    _claimManyFromArena(tokenIds, unstake, account, ringLevel, ringExpireTime, extraAmuletDays, amuletExpireTime);
  }

  function _claimManyFromArena(
    uint256[] calldata tokenIds, 
    bool unstake, 
    address account, 
    uint256 ringLevel, 
    uint256 ringExpireTime, 
    uint256 extraAmuletDays, 
    uint256 amuletExpireTime
  ) private {
    uint256[] memory packedFighters = ugFYakuza.getPackedFighters(tokenIds);
    if(tokenIds.length != packedFighters.length) revert MismatchArrays();
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    uint256 owed = 0;
    
    if(unstake) _removeFromOwnerStakedTokenList(_msgSender(), tokenIds);

    for (uint256 i; i < packedFighters.length; i++) {   
      owed += _claimFighter(tokenIds[i], unstake, account, ringLevel, ringExpireTime, extraAmuletDays, amuletExpireTime, unPackFighter(packedFighters[i]));     
      //set amounts array for batch transfer
      _amounts[i] = 1;
    }
    // Pay out earned $BLOOD
     if (owed > 0) {      
      uint256 MAXIMUM_BLOOD_SUPPLY = ugGame.MAXIMUM_BLOOD_SUPPLY();     
      uint256 normalizedSupply = uBlood.totalSupply()/1e18;
      // Pay out rewards as long as we did not reach max $BLOOD supply
      if (normalizedSupply < MAXIMUM_BLOOD_SUPPLY ) {
        if (normalizedSupply + owed > MAXIMUM_BLOOD_SUPPLY) { // If totalSupply + owed exceeds the maximum supply then pay out only the remainder
          owed = MAXIMUM_BLOOD_SUPPLY - normalizedSupply; // Pay out the rest and that's it, we reached the maximum $BLOOD supply (for now)
        }
        // Pay $BLOOD to the owner
        totalBloodEarned += owed;
        uBlood.mint(account, owed * 1 ether);
      }
    }
  
    if(unstake) {
      ugFYakuza.safeBatchTransferFrom(address(this), account, tokenIds, _amounts, ""); // send back Fighter
    }
    
    emit TokensClaimed(account, tokenIds, unstake, owed, block.timestamp);
  }

  function _claimFighter(
    uint256 tokenId, 
    bool unstake, 
    address account, 
    uint256 ringLevel, 
    uint256 ringExpireTime, 
    uint256 extraAmuletDays, 
    uint256 amuletExpireTime, 
    IUGFYakuza.FighterYakuza memory fighter
  ) private returns (uint256 owed ) {
    Stake memory stake = _fighterArena[tokenId];
    if(stake.owner != account && !_admins[_msgSender()]) revert InvalidOwner();
    if(unstake && block.timestamp - stake.stakeTimestamp < MINIMUM_DAYS_TO_EXIT) revert StakingCoolDown();

    owed = _calculateStakingRewards(tokenId, ringLevel, ringExpireTime, extraAmuletDays, amuletExpireTime, fighter);
    
    // steal and pay tax logic
    if (unstake) {
      if (randomizer.getSeeds(tokenId, owed,1)[0]%2 == 1) { // 50% chance of all $BLOOD stolen
        _payYakuzaTax(owed);
        emit BloodStolen(stake.owner, tokenId, owed);
        owed = 0; // Fighter lost all of his claimed $BLOOD right here
      }
      delete _fighterArena[tokenId];
      totalFightersStaked--;

      _updateIDStakedBalance(stake.owner, tokenId, 1, Operations.Sub);
      _updateIDUserTotalBalance(stake.owner, FIGHTER_INDEX, 1, Operations.Sub);
    } else {
      _payYakuzaTax(owed * YAKUZA_TAX_PERCENTAGE / 100); // percentage tax to staked Yakuza
      owed = owed * (100 - YAKUZA_TAX_PERCENTAGE) / 100; // remainder goes to Fighter owner
      
      // reset stake
      Stake memory newStake;
      newStake.bloodPerRank = 0;
      newStake.stakeTimestamp = uint32(block.timestamp);
      newStake.owner = stake.owner;
      _fighterArena[tokenId] = newStake;
    }
    //emit TokenClaimed(stake.owner, tokenId, unstake, owed, block.timestamp);
    return owed;
  }


  function stakeRing(uint256 tokenId) external nonReentrant whenNotPaused {
    address account = _msgSender();
    if(_ringAmuletUnstakeTimes[tokenId] + UNSTAKE_COOLDOWN > block.timestamp ) revert InvalidToken();
    if(ierc1155.balanceOf(account, tokenId) == 0) revert InvalidTokens({tokenId: tokenId});
    //check if user has a staked ring already
    if(_ownersOfStakedRings[account] != 0) revert MaximumAllowedActiveRings({tokenId: tokenId});
    _stakeRing(account, tokenId);
  }

  function _stakeRing(address account, uint256 tokenId) private {
    _totalRingsStaked++;
    _ownersOfStakedRings[account] = tokenId;   
    ugNFT.safeTransferFrom(account, address(this), tokenId, 1, "");
    delete _ringAmuletUnstakeTimes[tokenId];
    emit TokenStaked(account, tokenId);
  }

  function unstakeRing(uint256 tokenId) external nonReentrant {
    //make sure sender is ringowner
    if(_ownersOfStakedRings[_msgSender()] != tokenId) revert InvalidTokens({tokenId: tokenId});
    _unstakeRing(_msgSender(), tokenId);
  }

  function _unstakeRing(address account, uint256 tokenId) private  {
    _totalRingsStaked--;
    delete _ownersOfStakedRings[account];
    _ringAmuletUnstakeTimes[tokenId] = block.timestamp;
    ugNFT.safeTransferFrom(address(this), account, tokenId, 1, "");
    emit TokenUnStaked(account, tokenId);
  }

  function stakeAmulet(uint256 tokenId) external nonReentrant whenNotPaused {
    address account = _msgSender();
    if(_ringAmuletUnstakeTimes[tokenId] + UNSTAKE_COOLDOWN > block.timestamp) revert InvalidToken();
    if(ierc1155.balanceOf(account, tokenId) == 0) revert InvalidTokens({tokenId: tokenId});
    //check if user has a staked amulet already
    if(_ownersOfStakedAmulets[account] != 0) revert MaximumAllowedActiveAmulets({tokenId: tokenId});
    _stakeAmulet(account, tokenId);
  }

  function _stakeAmulet(address account, uint256 tokenId) private  {
    _totalAmuletsStaked++;
    _ownersOfStakedAmulets[account] = tokenId;    
    ugNFT.safeTransferFrom(account, address(this), tokenId, 1, "");
    delete _ringAmuletUnstakeTimes[tokenId];
    emit TokenStaked(account, tokenId);
  }

  function unstakeAmulet(uint256 tokenId) external nonReentrant {
    //make sure sender is amulet owner
    if(_ownersOfStakedAmulets[_msgSender()] != tokenId) revert InvalidTokens({tokenId: tokenId});
    _unstakeAmulet(_msgSender(), tokenId);
  }

  function _unstakeAmulet(address account, uint256 tokenId) private  {
    _totalAmuletsStaked--;
    delete _ownersOfStakedAmulets[account];
    _ringAmuletUnstakeTimes[tokenId] = block.timestamp;
    ugNFT.safeTransferFrom(address(this), account, tokenId, 1, "");
    emit TokenUnStaked(account, tokenId);
  }

  function unPackFighter(uint256 packedFighter) private pure returns (IUGFYakuza.FighterYakuza memory) {
    IUGFYakuza.FighterYakuza memory fighter;   
    fighter.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
    fighter.Gen = uint8(packedFighter>>1)%2;
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

  /////////////////////////////////////////
  //     Packed Balance Functions       //
  ///////////////////////////////////////
  
  /**
   * @notice Update the balance of a id for a given address
   * @param _address    Address to update id balance
   * @param _id         Id to update balance of
   * @param _amount     Amount to update the id balance
   * @param _operation  Which operation to conduct :
   *   Operations.Add: Add _amount to id balance
   *   Operations.Sub: Substract _amount from id balance
   */
  function _updateIDStakedBalance(address _address, uint256 _id, uint256 _amount, Operations _operation)
    internal
  {
    uint256 bin;
    uint256 index;

    // Get bin and index of _id
    (bin, index) = getIDBinIndex(_id);

    // Update balance
    stakedBalances[_address][bin] = _viewUpdateBinValue(stakedBalances[_address][bin], IDS_BITS_SIZE, index, _amount, _operation);
  }

  function _updateIDUserTotalBalance(address _address, uint256 _index, uint256 _amount, Operations _operation)
    internal
  {
    // Update balance
    userTotalBalances[_address] = _viewUpdateBinValue(userTotalBalances[_address], USER_TOTAL_BALANCES_BITS_SIZE, _index, _amount, _operation);
  }

  /**
   * @notice Update a value in _binValues
   * @param _binValues  Uint256 containing values of size IDS_BITS_SIZE (the token balances)
   * @param _index      Index of the value in the provided bin
   * @param _amount     Amount to update the id balance
   * @param _operation  Which operation to conduct :
   *   Operations.Add: Add _amount to value in _binValues at _index
   *   Operations.Sub: Substract _amount from value in _binValues at _index
   */
  function _viewUpdateBinValue(uint256 _binValues, uint256 bitsize, uint256 _index, uint256 _amount, Operations _operation)
    internal pure returns (uint256 newBinValues)
  {
    uint256 shift = bitsize * _index;
    uint256 mask = (uint256(1) << bitsize) - 1;

    if (_operation == Operations.Add) {
      newBinValues = _binValues + (_amount << shift);
      require(newBinValues >= _binValues, " OVERFLOW2");
      require(
        ((_binValues >> shift) & mask) + _amount < 2**bitsize, // Checks that no other id changed
        "OVERFLOW1"
      );

    } else if (_operation == Operations.Sub) {
      newBinValues = _binValues - (_amount << shift);
      require(newBinValues <= _binValues, " UNDERFLOW");
      require(
        ((_binValues >> shift) & mask) >= _amount, // Checks that no other id changed
        "viewUpdtBinVal: UNDERFLOW"
      );

    } else {
      revert("viewUpdtBV: INVALID_WRITE"); // Bad operation
    }

    return newBinValues;
  }

  /**
  * @notice Return the bin number and index within that bin where ID is
  * @param _id  Token id
  * @return bin index (Bin number, ID"s index within that bin)
  */
  function getIDBinIndex(uint256 _id)
    public pure returns (uint256 bin, uint256 index)
  {
    bin = _id / IDS_PER_UINT256;
    index = _id % IDS_PER_UINT256;
    return (bin, index);
  }

  /**
   * @notice Return amount in _binValues at position _index
   * @param _binValues  uint256 containing the balances of IDS_PER_UINT256 ids
   * @param _index      Index at which to retrieve amount
   * @return amount at given _index in _bin
   */
  function getValueInBin(uint256 _binValues, uint256 bitsize, uint256 _index)
    public pure returns (uint256)
  {
    // Mask to retrieve data for a given binData
    uint256 mask = (uint256(1) << bitsize) - 1;

    // Shift amount
    uint256 rightShift = bitsize * _index;
    return (_binValues >> rightShift) & mask;
  }

  function _viewUserStakedIdBalance(address _address, uint256 _id)
    internal view returns(uint256)
  {
    uint256 bin;
    uint256 index;

    // Get bin and index of _id
    (bin, index) = getIDBinIndex(_id);

    // return balance
    return getValueInBin(stakedBalances[_address][bin], IDS_BITS_SIZE, index);
  }

  //map user address to packed uint256 bins holding token ids
  mapping (address =>  mapping(uint256 => uint256)) internal _ownerStakedTokenList;
  //map tokenIds to owned indexes
  mapping(uint256 => uint256) internal _ownerStakedTokenIndexes;

   //ENUMERATION
  function _addToOwnerStakedTokenList(address _address, uint256[] memory _tokenIds)
    internal
  {    
    //get balance of fighters    
    uint newIndex = getValueInBin(userTotalBalances[_address], USER_TOTAL_BALANCES_BITS_SIZE, FIGHTER_INDEX);
    uint bin;
    uint index;
    for(uint i; i< _tokenIds.length;i++){
      //16 tokenIds per uint
      bin = newIndex / 16;
      index = newIndex % 16;
      // Update balance
      _ownerStakedTokenList[_address][bin] = _viewUpdateBinValue(_ownerStakedTokenList[_address][bin], 16, index, _tokenIds[i], Operations.Add);
      //update owner index
      bin = _tokenIds[i]/16;
      index = _tokenIds[i] % 16;
      //_updateOwnerTokenIndex(_address, _tokenId, _ownerIndex, _operation);
      _ownerStakedTokenIndexes[bin] = _viewUpdateBinValue(_ownerStakedTokenIndexes[bin], 16, index, newIndex, Operations.Add);
      newIndex++;
    }    
  }

  function _removeFromOwnerStakedTokenList(address _from, uint256[] memory _tokenIds)internal{    
    uint256 lastTokenIndex = getValueInBin(userTotalBalances[_from], USER_TOTAL_BALANCES_BITS_SIZE, FIGHTER_INDEX) - 1;
    //16 tokenIds per uint
    uint256 bin;
    uint256 index;
    uint256 removeTokenIndex;  
    uint256 lastTokenId;
    
    for(uint i; i< _tokenIds.length;i++){
    //16 tokenIds per uint
    lastTokenId = getValueInBin(_ownerStakedTokenList[_from][lastTokenIndex / 16], 16, lastTokenIndex % 16);
    //get token to be removed index
    bin = (_tokenIds[i])/ 16;
    index = (_tokenIds[i]) % 16;
    removeTokenIndex = getValueInBin(_ownerStakedTokenIndexes[bin], 16, index);  
    // When the token to delete is the last token, the swap operation is unnecessary    
    if (_tokenIds[i] != lastTokenId) {     
      Operations _operations;
      uint256 amount;
      if(lastTokenId > _tokenIds[i]){
        _operations = Operations.Add;
        amount = lastTokenId - _tokenIds[i];
      } else {
        _operations = Operations.Sub;
        amount = _tokenIds[i] - lastTokenId;
      }
     
      // Move the last token to the slot of the to-delete token
      _ownerStakedTokenList[_from][removeTokenIndex/16] = _viewUpdateBinValue(_ownerStakedTokenList[_from][removeTokenIndex/16], 16, removeTokenIndex%16, amount, _operations);
      uint256 indexDiff = lastTokenIndex - removeTokenIndex;
      //update new index for moved token by subtracting indexDiff
      _ownerStakedTokenIndexes[(lastTokenId)/16] = _viewUpdateBinValue(_ownerStakedTokenIndexes[(lastTokenId)/16], 16, (lastTokenId)%16, indexDiff, Operations.Sub);
      
    }   
    // This also deletes the contents at the last position of the array
    _ownerStakedTokenIndexes[_tokenIds[i]/16] = _viewUpdateBinValue(_ownerStakedTokenIndexes[_tokenIds[i]/16], 16, _tokenIds[i]%16, getValueInBin(_ownerStakedTokenIndexes[(_tokenIds[i])/16], 16, (_tokenIds[i])%16), Operations.Sub);
    // console.log('removeTokenIndex',removeTokenIndex);
    _ownerStakedTokenList[_from][lastTokenIndex / 16] = _viewUpdateBinValue(_ownerStakedTokenList[_from][lastTokenIndex / 16], 16, lastTokenIndex % 16, getValueInBin(_ownerStakedTokenList[_from][lastTokenIndex/16], 16, lastTokenIndex%16), Operations.Sub);
    
    if(lastTokenIndex > 0 ) lastTokenIndex--;
    }   
  }

  function tokenOfOwnerByIndex(address owner, uint256 _index) public view virtual returns (uint256) {
    require(_index < getValueInBin(userTotalBalances[owner], USER_TOTAL_BALANCES_BITS_SIZE, FIGHTER_INDEX), "owner index out of bounds");

    uint256 bin = _index/16;
    uint256 index = _index % 16;
    return getValueInBin(_ownerStakedTokenList[owner][bin], 16, index);
  } 

  /** ONLY ADMIN FUNCTIONS */
  function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
  

  /** ONLY OWNER FUNCTIONS */
  function setContracts(address _ugnft, address _ugFYakuza, address _blood, address _randomizer, address _ugGame) external onlyOwner {
    ugNFT = IUGNFT(_ugnft);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    ierc1155 = IERC1155(_ugnft);
    ierc1155FY = IERC1155(_ugFYakuza);
    uBlood = IUBlood(_blood);
    randomizer = IRandomizer(_randomizer);
    ugGame = IUGgame(_ugGame);
  }

  function setGameContract(address _ugGame) external onlyOwner {
    ugGame = IUGgame(_ugGame);
  }

  function setFighterCoolDown(uint256 timeInSec) external onlyOwner {
    MINIMUM_DAYS_TO_EXIT = timeInSec;
  }

  function setDailyBloodRatePerLevel(uint256 amount) external onlyOwner {
    DAILY_BLOOD_RATE_PER_LEVEL = amount;
  }

  function setRingBloodPerLevel(uint256 amount) external onlyOwner {
    RING_DAILY_BLOOD_PER_LEVEL = amount;
  }  

  function setPaused(bool paused) external onlyOwner {
    if (paused) _pause();
    else _unpause();
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

}