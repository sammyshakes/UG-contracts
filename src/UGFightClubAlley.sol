// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUGgame.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IRandomizer.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract UGFightClubAlley is Ownable, Pausable, ReentrancyGuard {

  struct Stake {
    uint64 bloodPerLevel;
    uint32 stakeTimestamp;
    address owner;
  }

  constructor(
    address _ugnft, 
    address _blood, 
    address _randomizer,
    address _devWallet
  ) {
    ugNFT = IUGNFT(_ugnft);
    uBlood = IUBlood(_blood);
    randomizer = IRandomizer(_randomizer);    
    devWallet = _devWallet;
  }
  
  //////////////////////////////////
  //          CONTRACTS          //
  /////////////////////////////////
  IUGNFT private ugNFT;
  IUBlood private uBlood;
  IRandomizer private randomizer; 
  IUGgame public ugGame;

  //////////////////////////////////
  //          EVENTS             //
  /////////////////////////////////
  event YakuzaTaxPaidFromRaids(uint256 amount, uint256 indexed timestamp);
  event FightClubOwnerBloodRewardClaimed(address indexed user);
  event FightClubsPaid(uint256 amount);

  //////////////////////////////////
  //          ERRORS             //
  /////////////////////////////////
  error MismatchArrays();
  //error InvalidTokens(uint256 tokenId);
  error InvalidOwner(address owner);
  error InvalidAddress();
  error InvalidTokenId();
  error Unauthorized();
  error OnlyEOA();
  error InvalidSize();

  //////////////////////////////////////////
  uint16 private DEV_CUT = 5;
  uint256 constant FIGHT_CLUB = 20000;

  uint256 public totalFightClubsStaked;
  uint256 public totalLevelsStaked;  
  uint256 public bloodPerLevel;
  address public devWallet;  

  mapping(address => bool) private _admins;
  //maps fightclub id => Stake
  mapping(uint256 => Stake) public stakedFightclubs;
  //maps owner => number of staked fightclubs
  mapping(address => uint256) public ownerTotalStakedFightClubs;
  // any rewards distributed when no Yakuza are staked
  uint256 private _unaccountedRewards = 0;  
  
  //Modifiers//
  modifier onlyAdmin() {
    if(!_admins[_msgSender()]) revert Unauthorized();
    _;
  }

  modifier onlyEOA() {
    if(tx.origin != msg.sender) revert OnlyEOA();
    _;
  }

  //////////////////////////////////
  //     EXTERNAL FUNCTIONS      //
  /////////////////////////////////
   
  function getStakedFightClubIDsForUser(address user) external view returns (uint256[] memory){
    //get balance of fight clubs
    uint256 numStakedFightClubs = ownerTotalStakedFightClubs[user];
    uint256[] memory _tokenIds = new uint256[](numStakedFightClubs);
    //loop through user balances until we find all the fighters
    uint count;
    for(uint i = 1; count<numStakedFightClubs; i++){
      if(stakedFightclubs[FIGHT_CLUB + i].owner == user){
        _tokenIds[count] = FIGHT_CLUB + i;
        count++;
      }
    }
    return _tokenIds;
  }

  function stakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
    //make sure is owned by sender
    if(!ugNFT.checkUserBatchBalance(msg.sender, tokenIds)) revert InvalidTokenId();    
    IUGNFT.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    if(tokenIds.length != fightclubs.length) revert MismatchArrays();
    
    _stakeFightclubs(msg.sender, tokenIds, fightclubs);
  }  
  
  function _stakeFightclubs(address account, uint256[] calldata tokenIds, IUGNFT.ForgeFightClub[] memory fightclubs) private {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    Stake memory myStake;
    uint256 levelCount;
    uint256 currLevel;
    for(uint i; i < tokenIds.length; i++){
      currLevel = fightclubs[i].level;
      levelCount += (currLevel * fightclubs[i].size);
      amounts[i] = 1;

      myStake.bloodPerLevel = uint64(bloodPerLevel);
      myStake.stakeTimestamp = uint32(block.timestamp);
      myStake.owner = account; 

      stakedFightclubs[tokenIds[i]] = myStake;
    }

    totalLevelsStaked += levelCount;
    totalFightClubsStaked += tokenIds.length;
    ownerTotalStakedFightClubs[account] += tokenIds.length;     

    ugNFT.safeBatchTransferFrom(account, address(this), tokenIds, amounts, "");
  }

  function claimFightClubs(uint256[] calldata tokenIds, bool unstake) public whenNotPaused {
    require(tokenIds.length > 0, "Empty Array");
    IUGNFT.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    if(tokenIds.length != fightclubs.length) revert MismatchArrays();
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    uint256 owed = 0;
    // Fetch the owner so we can give that address the $BLOOD.
    // If the same address does not own all tokenIds this transaction will fail.
    // This is especially relevant when the Game contract calls this function as the _msgSender() - it should NOT get the $BLOOD ofc.
    address account = stakedFightclubs[tokenIds[0]].owner;    
    
    Stake memory myStake;
    uint256 currLevel;
    uint256 levelCount;
  
    for (uint256 i; i < fightclubs.length; i++) {     
       
      account = stakedFightclubs[tokenIds[i]].owner;
      // The _admins[] check allows the Game contract to claim at level upgrades
      // and raid contract when raiding.
      if(account != _msgSender() && !_admins[_msgSender()]) revert InvalidOwner(_msgSender());

      owed += _calculateStakingRewards(tokenIds[i]);   

      if (unstake) {
        //tally levels to deduct from total levels staked
        currLevel = fightclubs[i].level;    
        levelCount += currLevel * fightclubs[i].size;

        // Delete old mapping
        delete stakedFightclubs[tokenIds[i]]; 
        //set amounts array for batch transfer
        _amounts[i] = 1;

      } else {
        // Just claim rewards
        myStake.bloodPerLevel = uint64(bloodPerLevel);
        myStake.stakeTimestamp = uint32(block.timestamp);
        myStake.owner = account;
        // Reset stake
        stakedFightclubs[tokenIds[i]] = myStake; 
      }      
    }
    
    // Pay out earned $BLOOD
    if (owed > 0) {    
      uint256 MAXIMUM_BLOOD_SUPPLY = ugGame.MAXIMUM_BLOOD_SUPPLY();      
      uint256 bloodTotalSupply = uBlood.totalSupply();
      uint256 normalizedSupply = bloodTotalSupply/1e18;
      // Pay out rewards as long as we did not reach max $BLOOD supply
      if (normalizedSupply < MAXIMUM_BLOOD_SUPPLY ) {
        if (normalizedSupply + owed > MAXIMUM_BLOOD_SUPPLY) { // If totalSupply + owed exceeds the maximum supply then pay out only the remainder
          owed = MAXIMUM_BLOOD_SUPPLY - normalizedSupply; // Pay out the rest and that's it, we reached the maximum $BLOOD supply (for now)
        }
        // Pay $BLOOD to the owner
        uBlood.mint(account, owed * 1 ether);
      }
    }
  
    if(unstake) {
      totalLevelsStaked -= levelCount; // Remove levels from total staked
      totalFightClubsStaked -= tokenIds.length; // Decrease the number of fightclubs staked
      ownerTotalStakedFightClubs[_msgSender()] -= tokenIds.length;
      ugNFT.safeBatchTransferFrom(address(this), account, tokenIds, _amounts, ""); // send back Fighter
    }
  }

  function calculateStakingRewards(uint256 tokenId) external view returns (uint256 owed) {
    return _calculateStakingRewards(tokenId);
  }

 function calculateAllStakingRewards(uint256[] memory tokenIds) external view returns (uint256 owed) {
    for (uint256 i; i < tokenIds.length; i++) {
      owed += _calculateStakingRewards(tokenIds[i]);
    }
    return owed;
  }

  function _calculateStakingRewards(uint256 tokenId) private view returns (uint256) {
    uint256 owed;
    IUGNFT.ForgeFightClub memory fightclub = ugNFT.getForgeFightClub(tokenId);
    Stake memory myStake = stakedFightclubs[tokenId];
    // Calculate portion of $BLOOD based on level * size
    if(bloodPerLevel  > myStake.bloodPerLevel) owed = (fightclub.level) * (fightclub.size) * (bloodPerLevel - myStake.bloodPerLevel); 
    return owed;
  }

  function payRevenueToFightClubs(uint256 amount) external onlyAdmin {
    _payFightClubs(amount);
  }

  function incrementLevelsStaked(uint256 amount) external onlyAdmin {
    totalLevelsStaked += amount;
  }
  
  function _payFightClubs(uint amount) private {
    if (totalLevelsStaked == 0) { // if there's no staked FightClubs
      _unaccountedRewards += amount; // keep track of $BLOOD that's due to all Yakuza      
      return;
    }
    // makes sure to include any unaccounted $BLOOD 
    uint256 bpr = (amount + _unaccountedRewards) / totalLevelsStaked;
    if(bpr > 5){
      bloodPerLevel += bpr;
      _unaccountedRewards = 0;      
    } else {
      //keep track till bpr gets large enough to distribute
      _unaccountedRewards += amount;
    }
    emit FightClubsPaid(amount);
  }

  function burnBlood(address account, uint256 amount) private {
    uBlood.burn(account , amount * 1 ether);
    //allocate 10% of all burned blood to dev wallet for continued development
    uBlood.mint(devWallet, amount * 1 ether * DEV_CUT / 100);
  }

  /** OWNER ONLY FUNCTIONS */

  function setContracts(
    address _ugNFT, 
    address _uBlood,
    address _randomizer
  ) external onlyOwner {
    ugNFT = IUGNFT(_ugNFT);
    uBlood = IUBlood(_uBlood);
    randomizer = IRandomizer(_randomizer);
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setGameContract(address _ugGame) external onlyOwner {
    ugGame = IUGgame(_ugGame);
  }

  function setDevCut(uint8 _devCut) external onlyOwner {
    DEV_CUT = _devCut;
  }

  function setDevWallet(address newWallet) external onlyOwner {
    if(newWallet == address(0)) revert InvalidAddress();
    devWallet = newWallet;
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
}