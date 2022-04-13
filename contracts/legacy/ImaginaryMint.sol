// contracts/imaginaryMint.sol - NOT PRODUCTION
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

contract ImaginaryMint is Ownable, Pausable, TokenOracle, Vault {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	address public asset;				//underlying asset
	uint256 public oracleDecimalOffset;	//price decimal offset

	address public imaginaryOracle;		//debt price
	uint256 public fallbackTokenPeg;	//peg price
	IImaginaryToken public iAsset;		//imaginary token

	uint256 public minimumMintRatio;	//
	uint256 public maximumMintRatio;	//(◕‿◕)

	uint256 public treasuryVaultID;		//0
	uint256 public liquidationFee;
	uint256 public operationFee;

	mapping(uint256 => uint256) public mintCollateral;
	mapping(uint256 => uint256) public mintAmount;

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

		address _asset,
		address _assetOracle,
		address _iAsset,
		address _author,

		uint256 mintRatio
	) Vault(name, symbol) {
		asset = _asset;
		iAsset = IImaginaryToken(_iAsset);

		oracleDecimalOffset = 4;

		minimumMintRatio	= mintRatio;
		maximumMintRatio	= 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
		fallbackTokenPeg	= 100000000;
		liquidationFee		=	 10;	//10%
		operationFee 		=    50;	//0.5%

		treasuryVaultID 				= 0;
		mintCollateral[treasuryVaultID] = 0;
		mintAmount[treasuryVaultID] 	= 0;

		transferOwnership(_author);

		_setAssetOracle(_assetOracle, 0);
	}

	modifier onlyVaultOwner(uint256 vaultID) {
        require(treasuryVaultID == vaultID || _exists(vaultID), "Does not exist");
        require((
			ownerOf(vaultID) == msg.sender ||
			(owner() == msg.sender && treasuryVaultID == vaultID)
		), "");
        _;
    }

	function createVault() external returns(uint256) {
		address owner = msg.sender;
		uint256 vaultID = _createVault(owner);

		mintCollateral[vaultID] = 0;
		mintAmount[vaultID] = 0;

		return(vaultID);
	}

	function lockAsset(uint256 vaultID, uint256 amount) external whenNotPaused {
		//will revert if cannot access tokens

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 newCollateral = mintCollateral[vaultID].add(amount);
        assert(newCollateral >= mintCollateral[vaultID]);

        mintCollateral[vaultID] = newCollateral;

        emit AssetLock(vaultID, amount);
    }

	function unlockAsset(uint256 vaultID, uint256 amount) external onlyVaultOwner(vaultID) {
        require(mintCollateral[vaultID] >= amount, "Vault does not have this.");

        uint256 newCollateral = mintCollateral[vaultID].sub(amount);

        if(mintAmount[vaultID] != 0) {
            require(isNutritional(newCollateral, mintAmount[vaultID]), "This would put vault at risk.");
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
		), "Vault cannot mint.");

        uint256 newAmount = mintAmount[vaultID].add(amount);
		uint256 fee = feeInCollateral(amount);

		uint256 newCollateral = mintCollateral[vaultID].sub(fee);
		uint256 treasuryCollateral = mintCollateral[treasuryVaultID].add(fee);

        require(isNutritional(newCollateral, newAmount), "Cannot mint.");

        require(_canLend(amount), "Not enough mintable.");

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
		//will revert if cannot access tokens
        require(mintAmount[vaultID] >= amount, "Vault does not need to.");

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

	function liquidate(uint256 vaultID, uint256 lqdrVaultID) external {
		require((
			(
				_exists(vaultID) &&
				!isNutritional(mintCollateral[vaultID], mintAmount[vaultID])
			) && (
				lqdrVaultID == treasuryVaultID ||
				msg.sender == ownerOf(lqdrVaultID)
			)
		), "Liquidation not allowed.");

		(uint256 va, ) = scale(
			mintCollateral[vaultID],
			mintAmount[vaultID]
		);
		// calculate
		uint256 fee = va.mul(liquidationFee).div(100);
		uint256 feeCollateral = fee.div(assetPrice());
		//liquidator reward - 25% of claimed
		uint256 reward = feeCollateral.mul(256).div(1024);
		uint256 feeMinusReward = feeCollateral.sub(reward);

		uint256 valueAfterFee = va.sub(fee);

		uint256 maxBorrow = valueAfterFee.mul(100).div(minimumMintRatio.add(1)).div(debtPrice()); //wanna set max borrow to just above min
		uint256 debtOffset = mintAmount[vaultID].sub(maxBorrow); //calculate debt offset

		uint256 newCollateral = mintCollateral[vaultID].sub(feeCollateral); //.add(feeColat)
		uint256 treasuryCollateral = mintCollateral[treasuryVaultID].add(feeMinusReward);
		
		//repay
		require((
			IERC20(address(iAsset)).balanceOf(msg.sender) >= debtOffset &&
			IERC20(address(iAsset)).allowance(msg.sender, address(this)) >= debtOffset
		), "Cannot return tokens.");
		
		IERC20(address(iAsset)).safeTransferFrom(msg.sender, address(this), debtOffset);
		mintAmount[vaultID] = mintAmount[vaultID].sub(debtOffset);

		//move colat
		if(lqdrVaultID != treasuryVaultID && reward > 0) {
        	mintCollateral[lqdrVaultID] = mintCollateral[lqdrVaultID].add(reward);
		} else {
			treasuryCollateral = treasuryCollateral.add(reward);
		}
		mintCollateral[vaultID] = newCollateral;
		mintCollateral[treasuryVaultID] = treasuryCollateral;

		emit VaultLiquidated(vaultID, debtOffset, feeCollateral, lqdrVaultID, reward);
	}


	//MINT CONTROL
	function pauseMint() external onlyOwner {
		_pause();
	}

	function unpauseMint() external onlyOwner {
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

	function mintBalance() public view returns(uint256) {
		return( IERC20(address(iAsset)).balanceOf(address(this)) );
	}

	function isNutritional(
		uint256 a,
		uint256 b
	) public view returns(bool) {
		return(getHealth(a, b) >= minimumMintRatio);
	}

	function feeInCollateral(uint256 amt) internal view returns(uint256) {
		uint256 fee = (
			amt.mul(operationFee).mul(debtPrice())
		).div(
			assetPrice().mul(10**oracleDecimalOffset)
		);
		//console.log("fee [0.5%] is [%s] when applied to [%s]", fee, amt);
		return( (fee > 0) ? fee : 0 );
	}

	function _canLend(uint256 amount) internal returns(bool) {
		bool hasEnough = (mintBalance() >= amount);
		if(!hasEnough) {
			iAsset.requestMint(address(this));
			return(mintBalance() >= amount);
		} else {
			return(hasEnough);
		}
	}

	function _returnToMint() internal {
		IERC20(address(iAsset)).approve(address(iAsset), 0);
		IERC20(address(iAsset)).approve(address(iAsset), mintBalance());
		iAsset.requestBurn(address(this));
	}
}
