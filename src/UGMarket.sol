// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUGWeapons.sol";
import "./interfaces/IUBlood.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//slither-disable-next-line locked-ether
contract Market {

    address public owner;

    struct Listing {
        uint256 id;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        address tokenAddress;
        address owner;
        bool active;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public listingsLength;

    mapping(address => bool) public validTokenAddresses;

    /*///////////////////////////////////////////////////////////////
                       MARKET MANAGEMENT SETTINGS
    //////////////////////////////////////////////////////////////*/

    uint256 public marketFee;
    uint256 public listingFee;
    bool public isMarketOpen;
    bool public emergencyDelisting;

    /////////////////////////////////////////////////////////////////
    //                          CONTRACTS                         //
    ////////////////////////////////////////////////////////////////
    IUGNFT public ugNFT;
    IUGFYakuza public ugFYakuza;
    IUGWeapons public ugWeapons;
    IUBlood public uBlood;

    /*///////////////////////////////////////////////////////////////
                                  EVENTS
    //////////////////////////////////////////////////////////////*/

    event OwnerUpdated(address indexed newOwner);
    event AddListingEv(
        uint256 listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 price
    );
    event UpdateListingEv(uint256 listingId, uint256 price);
    event CancelListingEv(uint256 listingId);
    event FulfillListingEv(uint256 listingId);

    /*///////////////////////////////////////////////////////////////
                                  ERRORS
    //////////////////////////////////////////////////////////////*/

    error Percentage0to100();
    error ClosedMarket();
    error InvalidListing();
    error InactiveListing();
    error InsufficientValue();
    error Unauthorized();
    error OnlyEmergency();
    error InvalidTokenAddress();
    error MismatchArrays();

    /*///////////////////////////////////////////////////////////////
                    CONTRACT MANAGEMENT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _ugnft, 
        address _ugFYakuza, 
        address _ugWeapons,
        address _blood, 
        uint256 _marketFee, 
        uint256 _listingFee
    ) {
        owner = msg.sender;
        marketFee = _marketFee;
        listingFee = _listingFee;
        ugNFT = IUGNFT(_ugnft);
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        ugWeapons = IUGWeapons(_ugWeapons);
        uBlood = IUBlood(_blood);
        validTokenAddresses[_ugnft] = true;
        validTokenAddresses[_ugFYakuza] = true;
        validTokenAddresses[_ugWeapons] = true;
    }

     modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setOwner(address _newOwner) external onlyOwner {
        //slither-disable-next-line missing-zero-check
        owner = _newOwner;
        emit OwnerUpdated(_newOwner);
    }

    function addTokenAddress(address _tokenAddress) external onlyOwner {
        validTokenAddresses[_tokenAddress] = true;
    }

    function removeTokenAddress(address _tokenAddress) external onlyOwner {
        delete validTokenAddresses[_tokenAddress];
    }

    /*///////////////////////////////////////////////////////////////
                      MARKET MANAGEMENT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function openMarket() external onlyOwner {
        if (emergencyDelisting) {
            delete emergencyDelisting;
        }
        isMarketOpen = true;
    }

    function closeMarket() external onlyOwner {
        delete isMarketOpen;
    }

    function allowEmergencyDelisting() external onlyOwner {
        emergencyDelisting = true;
    }

    function setMarketFee(uint256 newMarketFee) external onlyOwner {
        marketFee = newMarketFee;
    }

    function setListingFee(uint256 newListingFee) external onlyOwner {
        listingFee = newListingFee;
    }

    // If something goes wrong, we can close the market and enable emergencyDelisting
    //    After that, anyone can delist active listings
    //slither-disable-next-line calls-loop
    function emergencyDelist(uint256[] calldata listingIDs) external {
        if (!(emergencyDelisting && !isMarketOpen)) revert OnlyEmergency();

        uint256 len = listingIDs.length;
        //slither-disable-next-line uninitialized-local
        for (uint256 i; i < len; ) {
            uint256 id = listingIDs[i];
            //rewrite this by building arrays then use safeBatchTransfer
            Listing memory listing = listings[id];
            if (listing.active) {
                listings[id].active = false;
                IERC1155(listing.tokenAddress).safeTransferFrom(
                    address(this),
                    listing.owner,
                    listing.tokenId,
                    listing.amount,
                    ""
                );
            }
            unchecked {
                ++i;
            }
        }
        
    }

    /*///////////////////////////////////////////////////////////////
                        LISTINGS WRITE OPERATIONS
    //////////////////////////////////////////////////////////////*/
    //Listings can be multiple token ids but all from same contract
    function addListings(        
        address _tokenAddress,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        uint256[] calldata _prices
    ) external {
        if (!isMarketOpen) revert ClosedMarket();
        if (!validTokenAddresses[_tokenAddress]) revert InvalidTokenAddress();
        if(_tokenIds.length != _amounts.length) revert MismatchArrays();
        if(_tokenIds.length != _prices.length) revert MismatchArrays();

        uint256 id;
        uint256 totalListingFee;
        for(uint i; i < _tokenIds.length; i++){
            // overflow is unrealistic
            unchecked {
                id = listingsLength++;

                listings[id] = Listing(
                    id,
                    _tokenIds[i],
                    _amounts[i],
                    _prices[i],
                    _tokenAddress,
                    msg.sender,
                    true
                );
                totalListingFee += _prices[i];
                emit AddListingEv(id, _tokenAddress, _tokenIds[i], _amounts[i], _prices[i]);
            }
        }
        totalListingFee = totalListingFee * listingFee / 100;
        uBlood.burn(msg.sender, totalListingFee * 1 ether);
        IERC1155(_tokenAddress).safeBatchTransferFrom(msg.sender, address(this), _tokenIds, _amounts, "");        
    }

    function updateListing(uint256[] calldata ids, uint256[] calldata prices) external {
        if (!isMarketOpen) revert ClosedMarket();
        for(uint i; i < ids.length; i++){
            if (ids[i] >= listingsLength) revert InvalidListing();
            if (listings[ids[i]].owner != msg.sender) revert Unauthorized();

            listings[ids[i]].price = prices[i];
            emit UpdateListingEv(ids[i], prices[i]);
        }        
    }

    function cancelListings(uint256[] calldata ids, address _tokenAddress) external {
        Listing memory listing;
        uint256[] memory _tokenIds = new uint256[](ids.length);
        uint256[] memory _amounts = new uint256[](ids.length);

        for(uint i; i < ids.length; i++){
            if (ids[i] >= listingsLength) revert InvalidListing();

            listing = listings[ids[i]];

            if (!listing.active) revert InactiveListing();
            if (listing.owner != msg.sender) revert Unauthorized();
            if (listing.tokenAddress != _tokenAddress) revert InvalidTokenAddress();

            _tokenIds[i] = listing.tokenId;
            _amounts[i] = listing.amount;

            delete listings[ids[i]];

            emit CancelListingEv(ids[i]);

        }
        IERC1155(_tokenAddress).safeBatchTransferFrom( address(this), msg.sender, _tokenIds, _amounts, "");

    }

    function fulfillListings(uint256[] calldata ids, address _tokenAddress) external {
        if (!isMarketOpen) revert ClosedMarket();

        uint256 totalBloodFee;
        address listingOwner;
        Listing memory listing;        
        uint256[] memory _tokenIds = new uint256[](ids.length);
        uint256[] memory _amounts = new uint256[](ids.length);

        for(uint i; i < ids.length; i++){
            if (ids[i] >= listingsLength) revert InvalidListing();

            listing = listings[ids[i]];

            if (!listing.active) revert InactiveListing();

            listingOwner = listing.owner;
            if (msg.sender == listingOwner) revert Unauthorized();

            _tokenIds[i] = listing.tokenId;
            _amounts[i] = listing.amount;
            totalBloodFee += listing.price;

            //mint blood to seller
            uBlood.mint(listingOwner, listing.price * marketFee * 1 ether / 100);

            delete listings[ids[i]];

            emit FulfillListingEv(ids[i]);
        }
        //burn blood from buyer
        uBlood.burn(msg.sender, totalBloodFee * 1 ether);
        IERC1155(_tokenAddress).safeBatchTransferFrom( address(this), msg.sender, _tokenIds, _amounts, "");
    }

    function getListings(uint256 from, uint256 length)
        external
        view
        returns (Listing[] memory listing)
    {
        unchecked {
            uint256 numListings = listingsLength;
            if (from + length > numListings) {
                length = numListings - from;
            }

            Listing[] memory _listings = new Listing[](length);
            //slither-disable-next-line uninitialized-local
            for (uint256 i; i < length; ) {
                _listings[i] = listings[from + i];
                ++i;
            }
            return _listings;
        }
    }

    /** ERC 165 */
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