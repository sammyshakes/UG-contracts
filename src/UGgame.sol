// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IUGNFT.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGRaid.sol";
import "./interfaces/IUGgame.sol";
import "./interfaces/IUGForgeSmith.sol";


contract UGgame is IUGgame, Ownable, ReentrancyGuard, Pausable {

      //////////////////////////////////
     //          CONTRACTS           //
    //////////////////////////////////
    IUGNFT public ugNFT;
    IUGFYakuza public ugFYakuza;
    IUGRaid public ugRaid;
    IUBlood public uBlood;
    IUGArena public ugArena;
    IUGForgeSmith public ugForgeSmith;

      /////////////////////////////////
     //          EVENTS             //
    /////////////////////////////////
    event BloodBurned( uint256 indexed timestamp, uint256 amount);

      ////////////////////////////////
     //          ERRORS            //
    ////////////////////////////////
    error MismatchArrays();
    error InvalidAddress();
    error InvalidTokenId();
    error OnlyEOA(address txorigin, address sender);
    error InvalidSize(uint8 size, uint32 sweat, uint8 yak, uint i);
    error TooMany();
    error InvalidLevel();
    error InvalidSizes();
    error MaxSizeAllowed();
    error MaxLevelAllowed();
    error BloodError();
    error MustUpgradeLevel();
    error MustUpgradeSize();
    error MintNotActive();
    error NeedMoreFighters();

    //user total balances bit indexes
    uint256 internal constant FIGHTER_INDEX  = 1;
    uint256 internal constant RING_INDEX  = 2;
    uint256 internal constant AMULET_INDEX  = 3;
    uint256 internal constant FORGE_INDEX  = 4;
    uint256 internal constant FIGHT_CLUB_INDEX  = 5;

    uint32 constant RING = 5000;
    uint32 constant AMULET = 10000;
    uint32 constant FIGHTER = 100000;
    uint32 constant FORGE_MAX_SIZE = 5;
    uint32 constant FORGE_MAX_LEVEL = 35;
    uint32 constant FIGHT_CLUB_MAX_SIZE = 4;
    uint32 constant FIGHT_CLUB_MAX_LEVEL = 34;

    uint16 private FIGHTER_LEVEL_COST_ADJUSTMENT_PCT = 100;
    uint16 private RING_LEVEL_COST_ADJUSTMENT_PCT = 100;
    uint16 private AMULET_LEVEL_COST_ADJUSTMENT_PCT = 100;
    uint16 private FIGHTCLUB_LEVEL_COST_ADJUSTMENT_PCT = 100;
    uint16 private FORGE_LEVEL_COST_ADJUSTMENT_PCT = 100;
    uint16 private FORGE_SIZE_COST_ADJUSTMENT_PCT = 100;

    bool public FORGE_MINT_ACTIVE = true;
    bool public FIGHTCLUB_MINT_ACTIVE = false;
    bool public AMULET_MINT_ACTIVE = true;
    bool public RING_MINT_ACTIVE = true;

    uint256 public MIN_FIGHTERS_PER_RING = 3;
    uint256 public MIN_FIGHTERS_PER_AMULET =4;

    uint256 private FIGHTER_BASE_LEVEL_COST = 50;
    uint256 private RING_BASE_LEVEL_COST = 1000;
    uint256 private AMULET_BASE_LEVEL_COST = 2000;
    uint256 private FORGE_BASE_LEVEL_COST = 25000;
    uint256 private FORGE_BASE_SIZE_COST = 125000;  
    uint256 private FIGHT_CLUB_BASE_LEVEL_COST = 1000;

    uint256 public RING_BLOOD_MINT_COST = 2_000_000 ;
    uint256 public AMULET_BLOOD_MINT_COST = 2_000_000 ;
    uint256 public FORGE_BLOOD_MINT_COST = 2_000_000 ;
    uint256 public FIGHTCLUB_BLOOD_MINT_COST = 5_000_000 ;
    uint256 public MAXIMUM_BLOOD_SUPPLY = 2_500_000_000 ;

    uint256 private MAXIMUM_FIGHTCLUBS_PER_MINT = 5;
    uint256 private MAXIMUM_FIGHTCLUBS_PER_WALLET = 5;
    
    address private WITHDRAW_ADDRESS;
    address private devWallet;

    /** MODIFIERS */
    modifier onlyEOA() {
        if(tx.origin != _msgSender()) revert OnlyEOA({txorigin: tx.origin, sender: _msgSender()});
        _;
    }

    constructor(
        address _ugnft, 
        address _ugFYakuza, 
        address _ugArena, 
        address _ugRaid, 
        address _blood, 
        address _ugForgeSmith,
        address _devWallet
    ) {
        ugNFT = IUGNFT(_ugnft);
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        ugArena = IUGArena(_ugArena);
        ugRaid = IUGRaid(_ugRaid);
        uBlood = IUBlood(_blood);
        ugForgeSmith = IUGForgeSmith(_ugForgeSmith);
        devWallet = _devWallet;
    }

    /** MINTING FUNCTIONS */
    function mintRing() external whenNotPaused  nonReentrant onlyEOA {
        if(!RING_MINT_ACTIVE) revert MintNotActive();
        uint256 totalCost = RING_BLOOD_MINT_COST;
        // This will fail if not enough $BLOOD is available
        burnBlood(_msgSender(), totalCost);
        ugNFT.mintRingAmulet(_msgSender(),  1, true);
    }

    function mintAmulet() external whenNotPaused  nonReentrant onlyEOA {
        if(!AMULET_MINT_ACTIVE) revert MintNotActive();
        uint256 totalCost = AMULET_BLOOD_MINT_COST;
        // This will fail if not enough $BLOOD is available
        burnBlood(_msgSender(), totalCost);
        ugNFT.mintRingAmulet(_msgSender(),  1, false);
    }

    function mintFightClubs(uint amount) external whenNotPaused nonReentrant onlyEOA {
        if(!FIGHTCLUB_MINT_ACTIVE) revert MintNotActive();
        if(amount > MAXIMUM_FIGHTCLUBS_PER_MINT) revert TooMany();
        if (MAXIMUM_FIGHTCLUBS_PER_WALLET > 0 && 
            amount + ugNFT.getNftIDsForUser(_msgSender(), FIGHT_CLUB_INDEX).length > MAXIMUM_FIGHTCLUBS_PER_WALLET) revert TooMany();
        uint256 totalCost = FIGHTCLUB_BLOOD_MINT_COST * amount;
        // This will fail if not enough $BLOOD is available
        burnBlood(_msgSender(), totalCost);
        for(uint i;i<amount;i++){
            ugNFT.mintFightClubForge(_msgSender(), "", 1, 1, true);
        }
    }

    function mintForges(uint amount) external whenNotPaused nonReentrant onlyEOA{
        if(!FORGE_MINT_ACTIVE) revert MintNotActive();
        uint256 totalCost = FORGE_BLOOD_MINT_COST * amount;
        // This will fail if not enough $BLOOD is available
        burnBlood(_msgSender(), totalCost);
        for(uint i;i<amount;i++){
            ugNFT.mintFightClubForge(_msgSender(), "", 1, 1, false);
        }
    }

    function levelUpFighters(
        uint256[] calldata _tokenIds, 
        uint256[] memory _levelsToUpgrade, 
        bool _isStaked
    ) external whenNotPaused nonReentrant onlyEOA returns (uint256 totalBloodCost) {
        //require both argument arrays to be same length
        if(_tokenIds.length != _levelsToUpgrade.length) revert MismatchArrays(); 
        
        //if not staked, must be owned by msgSender
        if(!_isStaked) {
            if(!ugFYakuza.checkUserBatchBalance(_msgSender(), _tokenIds)) revert InvalidTokenId();
        } else if(!ugArena.verifyAllStakedByUser(_msgSender(), _tokenIds) ) revert InvalidTokenId();
  
        uint256[] memory fighters = ugFYakuza.getPackedFighters(_tokenIds);

        // calc blood cost
        for(uint256 i = 0; i < _tokenIds.length; i++){  
            //check to make sure not Yakuza
            if(unPackFighter(fighters[i]).isFighter){
                totalBloodCost += getFighterLevelUpBloodCost(unPackFighter(fighters[i]).level, _levelsToUpgrade[i]);
                _levelsToUpgrade[i] += unPackFighter(fighters[i]).level ;
            }
        }
        burnBlood(_msgSender(), totalBloodCost);

        // Claim $BLOOD before level up to prevent issues where higher levels would improve the whole staking period instead of just future periods
        // This also resets the stake and staking period
        //skip claiming if claimall within last 24 hours
        if (_isStaked && block.timestamp >  ugArena.getOwnerLastClaimAllTime(_msgSender()) + 1 days) {
            ugArena.claimManyFromArena(_tokenIds, false);
        }
        //level up fighters
        ugFYakuza.levelUpFighters(_tokenIds, _levelsToUpgrade);
        
    }

    function levelUpRing(
        uint256 tokenId, 
        uint256 _levelsToUpgrade        
    ) external whenNotPaused nonReentrant onlyEOA returns (uint256 totalBloodCost) {
        IUGNFT.RingAmulet memory ring;
        address account = _msgSender();
        uint256 numStakedFighters = ugArena.numUserStakedFighters(account);
        uint256 userStakedRingId = ugArena.getStakedRingIDForUser(account); 
        uint256 userStakedAmuletId = ugArena.getStakedAmuletIDForUser(account);   
        //ring must be staked to ARENA
        if(userStakedRingId != tokenId) revert InvalidTokenId();
        //get ring and amulet
        ring = ugNFT.getRingAmulet(tokenId);
        if(ring.level + _levelsToUpgrade > 10 && userStakedAmuletId == 0) revert InvalidLevel();
        
        //must have minimum number of staked fighters
        if(numStakedFighters < (ring.level + _levelsToUpgrade) * MIN_FIGHTERS_PER_RING) revert NeedMoreFighters(); 
           
        totalBloodCost = getRingLevelUpBloodCost(ring.level, _levelsToUpgrade, numStakedFighters);

        burnBlood(account, totalBloodCost);
        //level up rings
        ugNFT.levelUpRingAmulets(tokenId, ring.level + _levelsToUpgrade);
        
    }

    function levelUpAmulet(
        uint256 tokenId, 
        uint256 _levelsToUpgrade
    ) external whenNotPaused nonReentrant onlyEOA returns (uint256 totalBloodCost) {
        IUGNFT.RingAmulet memory amulet;
        address account = _msgSender();
        uint256 numStakedFighters = ugArena.numUserStakedFighters(account);
        uint256 userStakedAmuletId = ugArena.getStakedAmuletIDForUser(account);        
        //ring must be staked to ARENA
        if(userStakedAmuletId != tokenId) revert InvalidTokenId();
        //get amulet
        amulet = ugNFT.getRingAmulet(tokenId);
        
        require(numStakedFighters >= (amulet.level + _levelsToUpgrade) * MIN_FIGHTERS_PER_AMULET, "NEED_MORE_FIGHTERS") ; 
           
        totalBloodCost = getAmuletLevelUpBloodCost(amulet.level, _levelsToUpgrade, numStakedFighters);

        burnBlood(account, totalBloodCost);
        
        //level up amulet
        ugNFT.levelUpRingAmulets(tokenId, amulet.level + _levelsToUpgrade);
    }

    function levelUpFightClubs(
        uint256[] calldata tokenIds, 
        uint256[] memory _upgradeLevels, 
        uint256[] memory _upgradeSizes
    ) external whenNotPaused nonReentrant onlyEOA returns (uint256 totalBloodCost) {   
        if(tokenIds.length != _upgradeLevels.length) revert MismatchArrays(); 
        if(tokenIds.length != _upgradeSizes.length) revert MismatchArrays(); 
        IUGNFT.ForgeFightClub memory fclub;
        for(uint i; i< tokenIds.length; i++){
            fclub  = ugNFT.getForgeFightClub(tokenIds[i]);
            if(_upgradeSizes[i] > 1 || (_upgradeSizes[i] == 1 && fclub.size == FIGHT_CLUB_MAX_SIZE)) revert MaxSizeAllowed();
            if(_upgradeLevels[i] > 1 || (_upgradeLevels[i] == 1 && fclub.level == FIGHT_CLUB_MAX_LEVEL)) revert MaxLevelAllowed();
            totalBloodCost += getFightClubLevelUpBloodCost(fclub.level, fclub.size,  _upgradeLevels[i] == 1 ? 1 : 0, _upgradeSizes[i] == 1 ? 1 : 0);
            
            if(_upgradeLevels[i] == 1) fclub.level += 1;
            if(_upgradeSizes[i] == 1) fclub.size += 1;
            // add to fightclub ques for new levelTiers and sizeTiers if staked
            if(fclub.owner == address(ugRaid) && (_upgradeLevels[i] == 1|| _upgradeSizes[i] == 1)){
                
                ugRaid.addFightClubToQueueAfterLevelSizeUp(tokenIds[i],  _upgradeSizes[i] == 1 ? 1 : 0, _upgradeLevels[i] == 1 ? 1 : 0, fclub);
            }            
            _upgradeLevels[i] = fclub.level;
            _upgradeSizes[i] = fclub.size;
        }  
              
        burnBlood(_msgSender(), totalBloodCost);
        //level up fight clubs
        ugNFT.levelUpFightClubsForges(tokenIds,  _upgradeSizes, _upgradeLevels)[0];
         
    }

    function levelUpForges(uint256[] calldata tokenIds, uint256[] memory _levelsToUpgrade) 
        external whenNotPaused nonReentrant onlyEOA returns (uint256 totalBloodCost) 
    {   
        //forge size = weapon type, size 1 = knuckles
        if(tokenIds.length != _levelsToUpgrade.length) revert MismatchArrays(); 
        IUGNFT.ForgeFightClub[] memory forges = ugNFT.getForgeFightClubs(tokenIds);
        uint256[] memory sizes = new uint256[](tokenIds.length);
        uint newLevel;
        uint totalLevels;
        for(uint i; i< tokenIds.length; i++){
            newLevel = forges[i].level + _levelsToUpgrade[i];
            //check to make sure level does not violate size
            if(newLevel > FORGE_MAX_LEVEL) revert InvalidLevel();
            if(forges[i].size == 1 && newLevel > 7) revert MustUpgradeSize();
            if(forges[i].size == 2 && newLevel > 14) revert MustUpgradeSize();
            if(forges[i].size == 3 && newLevel > 21) revert MustUpgradeSize();
            if(forges[i].size == 4 && newLevel > 28) revert MustUpgradeSize();
            
            totalBloodCost += getForgeLevelUpBloodCost(forges[i].level, forges[i].size,  _levelsToUpgrade[i]);
           
            if(totalBloodCost == 0) revert BloodError();
            totalLevels += _levelsToUpgrade[i];
            //create size array of 0s
            sizes[i] = 0;
            _levelsToUpgrade[i] = newLevel;
            //tally total levels
            
           
        }        
        burnBlood(_msgSender(), totalBloodCost);
        //level up forges, returns upgraded forge
        ugForgeSmith.claimAllStakingRewards(_msgSender());
        ugForgeSmith.addToTotalForgeLevelStaked(totalLevels);
        ugNFT.levelUpFightClubsForges(tokenIds, sizes, _levelsToUpgrade);
    }

    function sizeUpForges(uint256[] calldata tokenIds) 
        external whenNotPaused nonReentrant onlyEOA returns (uint256 totalBloodCost) 
    {   
        //forge size = weapon type, size 1 = knuckles
        IUGNFT.ForgeFightClub[] memory forges = ugNFT.getForgeFightClubs(tokenIds);        
        uint256[] memory sizes = new uint256[](tokenIds.length);        
        uint256[] memory levels = new uint256[](tokenIds.length);
        for(uint i; i< tokenIds.length; i++){
            //make sure forge is required level for upgrade
            if(forges[i].size == 1 && forges[i].level < 7) revert MustUpgradeLevel();
            if(forges[i].size == 2 && forges[i].level < 14) revert MustUpgradeLevel();
            if(forges[i].size == 3 && forges[i].level < 21) revert MustUpgradeLevel();
            if(forges[i].size == 4 && forges[i].level < 28) revert MustUpgradeLevel();
            
            totalBloodCost += getForgeSizeUpBloodCost(forges[i].size);
            sizes[i] = forges[i].size + 1;
            levels[i] = 0;
            
        }        
        burnBlood(_msgSender(), totalBloodCost);
        //claim previous weapons
        ugForgeSmith.claimAllStakingRewards(_msgSender());
        //size up forge
        ugNFT.levelUpFightClubsForges(tokenIds, sizes, levels);
    }

    function getForgeLevelUpBloodCost(
        uint256 currentLevel, 
        uint256 currentSize, 
        uint256 levelsToUpgrade
    ) public view returns (uint256 totalBloodCost) {  

        //forge size = weapon type, size 1 = knuckles
        if(currentLevel == 0 && levelsToUpgrade == 0) revert InvalidLevel();
        totalBloodCost = 0;

        if (levelsToUpgrade == 0) totalBloodCost = _getForgeBloodCostPerLevel(currentLevel, currentSize);
            else if (levelsToUpgrade > 0){
                for (uint8 i = 1; i <= levelsToUpgrade; i++) {
                    totalBloodCost += _getForgeBloodCostPerLevel(currentLevel + i, currentSize);           
                }
            } 
        if(totalBloodCost == 0) revert BloodError();

        if(FORGE_LEVEL_COST_ADJUSTMENT_PCT != 100){
            //inflation adjustment logic
            return (totalBloodCost* FORGE_LEVEL_COST_ADJUSTMENT_PCT / 100  );
        }
        //inflation adjustment logic
        return totalBloodCost ;
    }

    function getForgeSizeUpBloodCost(uint16 currentSize) public view returns (uint256 totalBloodCost) {   
        //forge size = weapon type, size 1 = knuckles
        totalBloodCost = _getForgeBloodCostPerSize(currentSize + 1);
        if(totalBloodCost == 0) revert BloodError();
        if(FORGE_SIZE_COST_ADJUSTMENT_PCT != 100){
            //inflation adjustment logic
            return (totalBloodCost* FORGE_SIZE_COST_ADJUSTMENT_PCT / 100  );
        }
        return totalBloodCost ;
    }

    function _getForgeBloodCostPerLevel(uint256 level, uint256 size) private view returns (uint256 price) {
        //forge size = weapon type, size 1 = knuckles
        if (size == 0 || size > FORGE_MAX_SIZE) revert InvalidSizes();
        if (level == 0 || level > FORGE_MAX_LEVEL) revert InvalidLevel();
        if(level % 7 == 0){
            return (FORGE_BASE_LEVEL_COST*(2**(size-1)) * 7);
        }
        return (FORGE_BASE_LEVEL_COST*(2**(size-1)) * (level % 7));
    }

    function _getForgeBloodCostPerSize(uint256 size) private view returns (uint256 price) {
        if (size == 0 || size > FORGE_MAX_SIZE) revert InvalidSizes();
        return (FORGE_BASE_SIZE_COST*(2**(size-1)));
    }

    function getFightClubLevelUpBloodCost(uint16 currentLevel, uint16 currentSize, uint8 levelsToUpgrade, uint8 sizesToUpgrade) 
        public view returns (uint256 totalBloodCost) 
    {
        require(currentLevel >= 0, "Game: Invalid currentLevel");
        require(currentSize >= 0, "Game: Invalid currentSize");
        totalBloodCost = 0;

        if (levelsToUpgrade == 0 && sizesToUpgrade == 0) totalBloodCost = _getFightClubBloodCostPerLevel(currentLevel, currentSize);
        else if (levelsToUpgrade == 1){
            if(sizesToUpgrade == 1){
                totalBloodCost += _getFightClubBloodCostPerLevel(currentLevel + 1, currentSize + 1);
            } else{
                totalBloodCost += _getFightClubBloodCostPerLevel(currentLevel + 1, currentSize);
            }                   
            
        } else {//if only size is being upgraded  
            totalBloodCost += _getFightClubBloodCostPerLevel(currentLevel, currentSize + 1);                    
        }

        if(totalBloodCost == 0) revert BloodError();

        if(FIGHTCLUB_LEVEL_COST_ADJUSTMENT_PCT != 100){
            //inflation adjustment logic
            return (totalBloodCost* FIGHTCLUB_LEVEL_COST_ADJUSTMENT_PCT / 100 );
        }
        //inflation adjustment logic
        return totalBloodCost ;
    }

    function getSizeTier(uint8 size) private pure returns (uint8) {
        return size/5;
    }

    function _getFightClubBloodCostPerLevel(uint256 level, uint256 size) private view returns (uint256 price) {
        if (level == 0 || size == 0) return 0;
        return ((FIGHT_CLUB_BASE_LEVEL_COST + FIGHT_CLUB_BASE_LEVEL_COST*level)*5*(2**(size-1)));
    }

    function _getFighterBloodCostPerLevel(uint16 level) private view returns (uint256 price) {
        if (level == 0) return 0;        
        return (2*FIGHTER_BASE_LEVEL_COST + FIGHTER_BASE_LEVEL_COST*((level-1)**2));
    }

    function getFighterLevelUpBloodCost(uint16 currentLevel, uint256 levelsToUpgrade) public view  returns (uint256 totalBloodCost) {
        if(levelsToUpgrade == 0) revert InvalidLevel();

        totalBloodCost = 0;

        for (uint16 i = 1; i <= levelsToUpgrade; i++) {
        totalBloodCost += _getFighterBloodCostPerLevel(currentLevel + i);
        }
        if(totalBloodCost == 0) revert BloodError();

        if(FIGHTER_LEVEL_COST_ADJUSTMENT_PCT != 100){
            //inflation adjustment logic
            return (totalBloodCost * FIGHTER_LEVEL_COST_ADJUSTMENT_PCT / 100);
        }
        return totalBloodCost ;
    }

    function getRingLevelUpBloodCost(uint16 currentLevel, uint256 levelsToUpgrade, uint256 numFighters) public view  returns (uint256 totalBloodCost) {
        if(currentLevel == 0) revert InvalidLevel();
       
        totalBloodCost = 0;

        if (levelsToUpgrade == 0) totalBloodCost = _getRingBloodCostPerLevel(currentLevel, numFighters);
            else{
                for (uint16 i = 1; i <= levelsToUpgrade; i++) {
                    totalBloodCost += _getRingBloodCostPerLevel(currentLevel + i, numFighters);
                }
            }    
        if(totalBloodCost == 0) revert BloodError();

        if(RING_LEVEL_COST_ADJUSTMENT_PCT != 100){
            //inflation adjustment logic
            return (totalBloodCost* RING_LEVEL_COST_ADJUSTMENT_PCT / 100  );
        }
        //inflation adjustment logic
        return totalBloodCost ;
    }

    function _getRingBloodCostPerLevel(uint16 level, uint256 numFighters) private view returns (uint256 price) {
        if (level == 0) return 0;
        price = (RING_BASE_LEVEL_COST + RING_BASE_LEVEL_COST*((level - 1)**2)) ;
        //adjust based on number of fighters
        price += price * numFighters/200;
        return price;
    }
    
    function getAmuletLevelUpBloodCost(uint16 currentLevel, uint256 levelsToUpgrade, uint256 numFighters) public view  returns (uint256 totalBloodCost) {
        if(currentLevel == 0) revert InvalidLevel();
        
        totalBloodCost = 0;

        if (levelsToUpgrade == 0) totalBloodCost = _getAmuletBloodCostPerLevel(currentLevel, numFighters);
            else{
                for (uint16 i = 1; i <= levelsToUpgrade; i++) {
                    totalBloodCost += _getAmuletBloodCostPerLevel(currentLevel + i, numFighters);
                }
            }
        if(totalBloodCost == 0) revert BloodError();

        if(AMULET_LEVEL_COST_ADJUSTMENT_PCT != 100){
            //inflation adjustment logic
            return (totalBloodCost  * AMULET_LEVEL_COST_ADJUSTMENT_PCT / 100);
        }
        //inflation adjustment logic
        return totalBloodCost;
    }

    function _getAmuletBloodCostPerLevel(uint16 level, uint256 numFighters) private view returns (uint256 price) {
        if (level == 0) return 0;
        price = (AMULET_BASE_LEVEL_COST + AMULET_BASE_LEVEL_COST*((level - 1)**2)) ;
        price += price * numFighters/200;
    }

    function burnBlood(address account, uint256 amount) private {
        uBlood.burn(account, amount * 1 ether);
        //allocate 10% of all burned blood to dev wallet for continued development
        uBlood.mint(devWallet, amount * 1 ether /10 );
        emit BloodBurned(block.timestamp, amount*90/100);
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

    /** OWNER ONLY FUNCTIONS */
    function setContracts(address _uBlood, address _ugFYakuza, address _ugNFT, address _ugArena, address _ugForgeSmith, address _ugRaid) external onlyOwner {
        uBlood = IUBlood(_uBlood);
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        ugNFT = IUGNFT(_ugNFT);
        ugArena = IUGArena(_ugArena);
        ugForgeSmith = IUGForgeSmith(_ugForgeSmith);
        ugRaid = IUGRaid(_ugRaid);
    }
    
    function setPaused(bool paused) external onlyOwner {
        if (paused) _pause();
        else _unpause();
    }

    function setMaxFightClubsPerMint(uint256 amt) external onlyOwner {
        MAXIMUM_FIGHTCLUBS_PER_MINT = amt;
    }

    function setMaxFightClubsPerWallet(uint256 amt) external onlyOwner {
        MAXIMUM_FIGHTCLUBS_PER_WALLET = amt;
    }

    function setFighterBaseLevelCost(uint256 newCost) external onlyOwner {
        FIGHTER_BASE_LEVEL_COST = newCost;
    }

    function setRingBaseLevelCost(uint256 newCost) external onlyOwner {
        RING_BASE_LEVEL_COST = newCost;
    }

    function setAmuletBaseLevelCost(uint256 newCost) external onlyOwner {
        AMULET_BASE_LEVEL_COST = newCost;
    }

    function setFightClubBaseLevelCost(uint256 newCost) external onlyOwner {
        FIGHT_CLUB_BASE_LEVEL_COST = newCost;
    }

    function setForgeBaseLevelCost(uint256 newCost) external onlyOwner {
        FORGE_BASE_LEVEL_COST = newCost;
    }

    function setForgeBaseSizeCost(uint256 newCost) external onlyOwner {
        FORGE_BASE_SIZE_COST = newCost;
    }

    function setFighterLevelCostAdjustmentPct(uint16 pct) external onlyOwner {
        FIGHTER_LEVEL_COST_ADJUSTMENT_PCT = pct;
    }

    function setRingLevelCostAdjustmentPct(uint16 pct) external onlyOwner {
        RING_LEVEL_COST_ADJUSTMENT_PCT = pct;
    }

    function setAmuletLevelCostAdjustmentPct(uint16 pct) external onlyOwner {
        AMULET_LEVEL_COST_ADJUSTMENT_PCT = pct;
    }
    

    function setFightClubLevelCostAdjustmentPct(uint16 pct) external onlyOwner {
        FIGHTCLUB_LEVEL_COST_ADJUSTMENT_PCT = pct;
    }

    function setMaximumBloodSupply(uint256 number) external onlyOwner {
        MAXIMUM_BLOOD_SUPPLY = number;
    }

    function setForgeMintActive(bool active) external onlyOwner {
        FORGE_MINT_ACTIVE = active;
    }

    function setFightClubMintActive(bool active) external onlyOwner {
        FIGHTCLUB_MINT_ACTIVE = active;
    }

    function setRingMintActive(bool active) external onlyOwner {
        RING_MINT_ACTIVE = active;
    }

    function setAmuletMintActive(bool active) external onlyOwner {
        AMULET_MINT_ACTIVE = active;
    }

    function setMinimumFightersPerAmulet(uint256 number) external onlyOwner {
        MIN_FIGHTERS_PER_AMULET = number;
    }

    function setMinimumFightersPerRing(uint256 number) external onlyOwner {
        MIN_FIGHTERS_PER_RING = number;
    }

    function setRingBloodMintCost(uint256 number) external onlyOwner {
        RING_BLOOD_MINT_COST = number;
    }

    function setAmuletBloodMintCost(uint256 number) external onlyOwner {
        AMULET_BLOOD_MINT_COST = number;
    }

    function setFightClubBloodMintCost(uint256 number) external onlyOwner {
        FIGHTCLUB_BLOOD_MINT_COST = number;
    }

    function setForgeBloodMintCost(uint256 number) external onlyOwner {
        FORGE_BLOOD_MINT_COST = number;
    }

    function setDevWallet(address newWallet) external onlyOwner {
        devWallet = newWallet;
    }
    
    function setWithdrawAddress(address addr) external onlyOwner {
        if(addr == address(0)) revert InvalidAddress();
        WITHDRAW_ADDRESS = addr;
    }
    
    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = WITHDRAW_ADDRESS.call{value: amount}("");
        require(sent, "Game: Failed to send funds");
    }
}