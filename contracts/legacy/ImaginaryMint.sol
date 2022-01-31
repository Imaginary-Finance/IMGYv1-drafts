// contracts/imaginaryMint.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./lib/oracle/OracleToken.sol";
//import "./lib/oracle/OracleLP.sol";

import "./lib/Vault.sol";

import "./lib/interfaces/IImaginaryToken.sol";

//import "hardhat/console.sol";

contract ImaginaryMint is Ownable, Pausable, ReentrancyGuard, TokenOracle, Vault {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;

	address public asset;				//underlying asset
	uint256 public oracleDecimalOffset;	//price decimal offset
	uint256 public collateralDecimalOffset;

	address public imaginaryOracle;		//debt price
	uint256 public fallbackTokenPeg;	//peg price
	IImaginaryToken public iAsset;		//imaginary token

	address public author;				//authorized value pool
	uint256 public claimRatio;			//liquidation claim

	uint256 public debtRaiseRatio;  	//
	uint256 public minimumMintRatio;	//cannot mint morth than value
	uint256 public maximumMintRatio;	//negative interest loans (◕‿◕)

	uint256 public treasuryVaultID;		//0
	uint256 public operationFee;		//0.5%

									//interest bearing assets
	mapping(uint256 => bool) public applyMaximumRatio;
	
	mapping(uint256 => uint256) public mintCollateral;
	mapping(uint256 => uint256) public mintAmount;
	mapping(uint256 => address) public mintOwner;

	event AssetLock(
		uint256 vaultID,
		uint256 amount
	);
	event AssetUnlock(
		uint256 vaultID,
		uint256 amount
	);
	event Minted(
		uint256 vaultID,
		uint256 amount,
		uint256 fee
	);
	event Returned(
		uint256 vaultID,
		uint256 amount,
		uint256 fee
	);

	event VaultCreated(
		uint256 vaultID,
		address owner
	);
	event VaultClosed(
		uint256 vaultID,
		address owner
	);

	event VaultLiquidated(
		uint256 vaultID,
		uint256 resolved,
		uint256 claimed,

		uint256 feeVault,
		uint256 fee
	);

    constructor(
		string memory name,
		string memory symbol,

		//address owner,

		address _asset,
		address _assetOracle,
		address _iAsset,
		address _author,
		address _treasurer,

		uint256 raisingRatio,
		uint256 mintRatio
	) Vault(name, symbol) {
		asset = _asset;

		iAsset = IImaginaryToken(_iAsset);
		author = _author;

		oracleDecimalOffset = 4;
		collateralDecimalOffset = 8;

		debtRaiseRatio		= raisingRatio;
		minimumMintRatio	= mintRatio;
		fallbackTokenPeg	= 100000000;
		//if set, will trigger healthy liquidations
		maximumMintRatio	= 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
		operationFee 		=    50;	//0.5%
		claimRatio			= 15000;	//150%

		treasuryVaultID 				= 0;
		mintCollateral[treasuryVaultID] = 0;
		mintAmount[treasuryVaultID] 	= 0;

		transferOwnership(_treasurer);
		
		_setAssetOracle(_assetOracle, fallbackTokenPeg);
	}

	modifier onlyVaultOwner(uint256 vaultID) {
        require(_exists(vaultID), "Does not exist");
        require(ownerOf(vaultID) == msg.sender, "");
        _;
    }

	function createVault() external {
		address owner = msg.sender;
		uint256 vaultID = _createVault(owner);

		mintOwner[vaultID] = owner;
		mintCollateral[vaultID] = 0;
		mintAmount[vaultID] = 0;

		emit VaultCreated(vaultID, owner);
	}

	function lockAsset(uint256 vaultID, uint256 amount) external whenNotPaused {
		require(IERC20(asset).allowance(msg.sender, address(this)) >= amount, "Mint: I cannot acces those.");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 newCollateral = mintCollateral[vaultID].add(amount);
        assert(newCollateral >= mintCollateral[vaultID]);

        mintCollateral[vaultID] = newCollateral;

        emit AssetLock(vaultID, amount);
    }

	function unlockAsset(uint256 vaultID, uint256 amount) external onlyVaultOwner(vaultID) nonReentrant {
        require(mintCollateral[vaultID] >= amount, "Mint: Vault does not contain that amount of assets.");

        uint256 newCollateral = mintCollateral[vaultID].sub(amount);

        if(mintAmount[vaultID] != 0) {
            require(isNutritional(newCollateral, mintAmount[vaultID]), "Mint: This would put vault at risk of liquidation.");
        }

        mintCollateral[vaultID] = newCollateral;
        IERC20(asset).safeTransfer(msg.sender, amount);

        emit AssetUnlock(vaultID, amount);
    }

    function mintToken(uint256 vaultID, uint256 amount) external whenNotPaused onlyVaultOwner(vaultID) {
		require((
			vaultID != treasuryVaultID &&
			mintCollateral[vaultID] > 0 &&
			amount > 0
		), "Mint: Cannot mint with these arguments.");

        uint256 newAmount = mintAmount[vaultID].add(amount);
		uint256 fee = feeInCollateral(amount);

		uint256 newCollateral = mintCollateral[vaultID].sub(fee);
		uint256 treasuryCollateral = mintCollateral[treasuryVaultID].add(fee);

        require(isNutritional(mintCollateral[vaultID], newAmount), "Mint: Cannot mint against these assets.");
		
		bool hasFunds = _canLend(amount);
        require(hasFunds, "Mint: Can not mint above the debt ceiling.");

		assert(
			(newAmount > mintAmount[vaultID]) && 
			(newCollateral < mintCollateral[vaultID]) &&
			(treasuryCollateral > mintCollateral[treasuryVaultID])
		);

		IERC20(address(iAsset)).safeTransfer(msg.sender, amount);

        mintAmount[vaultID] = newAmount;
		mintCollateral[vaultID] = newCollateral;
		mintCollateral[treasuryVaultID] = treasuryCollateral;

        emit Minted(vaultID, amount, fee);
    }

    function returnToken(uint256 vaultID, uint256 amount) external onlyVaultOwner(vaultID) {
        require((
			IERC20(address(iAsset)).balanceOf(msg.sender) >= amount &&
			IERC20(address(iAsset)).allowance(msg.sender, address(this)) >= amount
		), "Mint: Cannot return tokens.");
        require(mintAmount[vaultID] >= amount, "Mint: Vault does not need to return this amount.");

		uint256 fee = feeInCollateral(amount);
		uint256 newAmount = mintAmount[vaultID].sub(amount);

		uint256 newCollateral = mintCollateral[vaultID].sub(fee);
		uint256 treasuryCollateral = mintCollateral[treasuryVaultID].add(fee);

		assert(
			(newAmount < mintAmount[vaultID]) && 
			(newCollateral < mintCollateral[vaultID]) &&
			(treasuryCollateral > mintCollateral[treasuryVaultID])
		);

		IERC20(address(iAsset)).safeTransferFrom(msg.sender, address(this), amount);
		_returnToMint();

		mintAmount[vaultID] = newAmount;
		mintCollateral[vaultID] = newCollateral;
		mintCollateral[treasuryVaultID] = treasuryCollateral;

        emit Returned(vaultID, amount, fee);
    }



	//TODO: LIQUIDATIONS
	function liquidate(uint256 vaultID, uint256 lqdrVaultID) external nonReentrant {
		require((
			_exists(vaultID) &&
			mintAmount[vaultID] > 0 &&
			isVaultUnhealthy(vaultID)
		), "Mint: Liquidation not allowed on this vault.");
		address lqdr = msg.sender;
        require((
			(author == address(0) && (
				lqdrVaultID == treasuryVaultID ||
				lqdr == ownerOf(lqdrVaultID)
			)) ||
			author == lqdr
		), "Mint: Not authorized to liquidate.");

		(uint256 va, uint256 vi) = scale(
			mintCollateral[vaultID],
			mintAmount[vaultID]
		);

		uint256 maxValue = va.mul(100).div(minimumMintRatio);
		uint256 maxAmount = maxValue.div(debtPrice());
		
		//Amount of unhealthy issued assets
		uint256 diff = mintAmount[vaultID].sub(maxAmount);

		require((
			IERC20(address(iAsset)).balanceOf(lqdr) >= diff &&
			IERC20(address(iAsset)).allowance(lqdr, address(this)) >= diff
		), "Mint: Cannot return tokens.");

		uint256 claimedCollateral = ( //150% of the debt removed
			diff.mul(claimRatio).mul(debtPrice())
		).div(
			assetPrice().mul(10**oracleDecimalOffset)
		);

		uint256 newCollateral = mintCollateral[vaultID].sub(claimedCollateral);
		uint256 treasuryCollateral = mintCollateral[treasuryVaultID].add(claimedCollateral);
		uint256 lqdrReward = 0;

		//give spoils to lqdr if it's not treasury
		if(lqdrVaultID != treasuryVaultID) {
			lqdrReward = feeInCollateral(diff).mul(100); //0.5% to 50%
			treasuryCollateral = mintCollateral[treasuryVaultID].add(claimedCollateral.sub(lqdrReward));
		}

		assert(
			(newCollateral < mintCollateral[vaultID]) &&
			(treasuryCollateral > mintCollateral[treasuryVaultID])
		);

		IERC20(address(iAsset)).safeTransferFrom(lqdr, address(this), diff);

		mintCollateral[vaultID] = newCollateral;
		mintAmount[vaultID] = maxAmount;
		mintCollateral[treasuryVaultID] = treasuryCollateral;
		if(lqdrVaultID != treasuryVaultID) {
			mintCollateral[lqdrVaultID] = mintCollateral[lqdrVaultID].add(lqdrReward);
		}

		emit VaultLiquidated(vaultID, diff, claimedCollateral, lqdrVaultID, lqdrReward);
	}


	//MINT CONTROL
	function pauseMint() external onlyOwner whenNotPaused {
		_pause();
	}

	function unpauseMint() external onlyOwner whenPaused {
		_unpause();
	}

	//helper buddies
	function scale(
		uint256 assets,
		uint256 iassets
	) internal view returns(uint256, uint256) {
		uint256 assetValue = assets.mul(assetPrice());
		uint256 iassetValue = iassets.mul(debtPrice());
		return(assetValue, iassetValue);
	}

	function getHealth(
		uint256 assets,
		uint256 iassets
	) public view returns(uint256) {
		if(assets == 0 || iassets == 0) {
			return(maximumMintRatio.sub(1));
		}

		(uint256 va, uint256 vi) = scale(assets, iassets);

		uint256 health = va.mul(100).div(vi);
		return(health);
	}

	function debtPrice() public view returns(uint256) {
		uint256 truePrice = fallbackTokenPeg;
        if(imaginaryOracle != address(0)) {
			(,int256 price,,,) = Oracle(imaginaryOracle).latestRoundData();
			truePrice = uint256(price);
		}
		return( truePrice /* debt peg or iAsset oracle */);
	}

	function mintCeiling() public returns(uint256) {
		return( iAsset.mintedSupply(address(this)) /* TOTAL iAssets that this mint has minted. */);
	}

	function mintBalance() public view returns(uint256) {
		return( IERC20(address(iAsset)).balanceOf(address(this)) );
	}

	function isNutritional(
		uint256 a,
		uint256 b
	) public view returns(bool) {
		return(getHealth(a, b) >= minimumMintRatio);
	}

	function isVaultUnhealthy(
		uint256 vaultID
	) public view returns(bool) {
		return(getHealth(mintCollateral[vaultID], mintAmount[vaultID]) >= minimumMintRatio);
	}

	function feeInCollateral(uint256 amt) internal view returns(uint256) {
		uint256 fee = (
			amt.mul(operationFee).mul(debtPrice())
		).div(
			assetPrice().mul(10**oracleDecimalOffset)
		);
		//console.log("fee [0.5%] is [%s] when applied to [%s]", fee, amt);
		if(fee > 0) {
			return(fee);
		}
		return(0);
	}

	function openTreasury() external onlyOwner {
		require(mintCollateral[treasuryVaultID] > 0, "Mint: Cannot transfer.");
		uint256 amount = mintCollateral[treasuryVaultID];

        IERC20(asset).safeTransferFrom(address(this), owner(), amount);
        mintCollateral[treasuryVaultID] = 0;

        emit AssetUnlock(treasuryVaultID, amount);
	}

	function _canLend(uint256 amount) internal returns(bool) {
		//TODO: CRITERIA FOR MINTING
		bool hasEnough = (mintBalance() >= amount);
		if(!hasEnough && !paused()) {
			iAsset.requestMint(address(this));
			return((mintBalance() >= amount));
		} else if (hasEnough) {
			return(true);
		} else {
			return(false);
		}
	}

	function _returnToMint() internal {
		if(!paused()) {
			IERC20(address(iAsset)).approve(address(iAsset), 0);
			IERC20(address(iAsset)).approve(address(iAsset), mintBalance());
			iAsset.requestBurn(address(this));
		}
	}
}
