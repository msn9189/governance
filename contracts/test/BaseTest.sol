// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import "../interfaces/IBribeFactory.sol";
import "../factories/GaugeFactory.sol";
import { Voter } from "../Voter.sol";
import { VoteEscrow } from "../VoteEscrow.sol";

contract IonicToken is ERC20 {
  constructor() ERC20("IONIC", "ION", 18) {}

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}

contract BaseTest is Test {
  GaugeFactory public gaugeFactory;
  Voter public voter;
  VoteEscrow public ve;
  IonicToken ionicToken = new IonicToken();
  address proxyAdmin = address(123);
  address bridge1 = address(321);

  function setUp() public {
    ionicToken = new IonicToken();

    VoterRolesAuthority voterRolesAuthImpl = new VoterRolesAuthority();
    TransparentUpgradeableProxy rolesAuthProxy = new TransparentUpgradeableProxy(
      address(voterRolesAuthImpl),
      proxyAdmin,
      ""
    );
    VoterRolesAuthority voterRolesAuth = VoterRolesAuthority(address(rolesAuthProxy));
    voterRolesAuth.initialize(address(this));

    GaugeFactory impl = new GaugeFactory();
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdmin, "");

    gaugeFactory = GaugeFactory(address(proxy));
    gaugeFactory.initialize(voterRolesAuth);

    VoteEscrow veImpl = new VoteEscrow();
    TransparentUpgradeableProxy veProxy = new TransparentUpgradeableProxy(address(veImpl), proxyAdmin, "");
    ve = VoteEscrow(address(veProxy));
    ve.initialize("veIonic", "veION", address(ionicToken));

    vm.chainId(ve.ARBITRUM_ONE());

    // TODO
    IBribeFactory bribeFactory = IBribeFactory(address(0));

    Voter voterImpl = new Voter();
    TransparentUpgradeableProxy voterProxy = new TransparentUpgradeableProxy(address(voterImpl), proxyAdmin, "");
    voter = Voter(address(voterProxy));
    voter.initialize(address(ve), address(gaugeFactory), address(bribeFactory), voterRolesAuth);

    vm.prank(ve.owner());
    ve.addBridge(bridge1);
  }

  // VoteEscrow 
  // [METADATA STORAGE]
  function testVersion() public {
    string memory version = ve.version();

    assertEq(version, "1.0.0", "testVersion/incorrect-version");
  }

  function testSetTeam() public {
    address newTeam = address(999);

    ve.setTeam(newTeam);
    
    assertEq(newTeam, address(999), "testSetTeam/incorrect-team");
  }

  function testTokenURI() public {
    vm.expectRevert("Query for nonexistent token");

    string memory uri = ve.tokenURI(555);

    // TODO returns empty URI for existing tokens
  }

  // [ERC721 BALANCE/OWNER STORAGE]
  function testOwnerOf() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    address owner = ve.ownerOf(tokenId);

    assertEq(owner, address(this), "testOwnerOf/incorrect-owner");
  }

  function testBalanceOf() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    uint256 balance = ve.balanceOf(address(this));

    assertEq(balance, 1, "testOwnerOf/incorrect-balance");
  }

  // [ERC721 APPROVAL STORAGE]
  function testApprovals() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    address approveAddress = address(999);

    ve.approve(approveAddress, tokenId);

    address approvedAddress = ve.getApproved(tokenId);

    assertEq(approveAddress, approvedAddress, "testApprovals/incorrect-approval");

    ve.setApprovalForAll(approveAddress, true);

    bool approvalStatus = ve.isApprovedForAll(address(this), approveAddress);

    assertEq(approvalStatus, true, "testApprovals/incorrect-approval-status");

    bool isApprovedOrOwner = ve.isApprovedOrOwner(approveAddress, tokenId);

    assertEq(isApprovedOrOwner, true, "testApprovals/incorrect-isApprovedOrOwner-status");

    isApprovedOrOwner = ve.isApprovedOrOwner(address(888), tokenId); // random address

    assertEq(isApprovedOrOwner, false, "testApprovals/incorrect-isApprovedOrOwner-random-address");
  }

  // [ERC721 LOGIC]
  function testTransferFrom() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    address receiverOfTransfer = address(999);

    uint256 ownershipsChangeBefore = ve.ownership_change(tokenId);
    assertEq(ownershipsChangeBefore, 0, "testTransferFrom/incorrect-ownership-change-before");

    ve.transferFrom(address(this), receiverOfTransfer, tokenId);

    uint256 ownershipsChangeAfter = ve.ownership_change(tokenId);
    assertEq(ownershipsChangeAfter, 1, "testTransferFrom/incorrect-ownership-change-after");

    assertEq(ve.balanceOf(address(this)), 0, "testTransferFrom/incorrect-sender-balance");
    assertEq(ve.balanceOf(receiverOfTransfer), 1, "testTransferFrom/incorrect-receiver-balance");

    vm.prank(receiverOfTransfer);

    ve.safeTransferFrom(receiverOfTransfer, address(444), tokenId);
    assertEq(ve.balanceOf(address(444)), 1, "testTransferFrom/incorrect-safeTransfer-balance");
  }

  // [ERC165 LOGIC]
  function testSupportsInterface() public {
    vm.chainId(ve.ARBITRUM_ONE());

    bool value = ve.supportsInterface(0x01ffc9a7);

    assertEq(value, true, "testSupportsInterface/invalid-interface");
  }

  // [INTERNAL MINT/BURN LOGIC]
  function testTokenOfOwnerByIndex() public {
    vm.chainId(ve.ARBITRUM_ONE());

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    uint256 tokenId = ve.create_lock(20e18, 52 weeks);

    uint256 tokenIdStored = ve.tokenOfOwnerByIndex(address(this), 0);

    assertEq(tokenId, tokenIdStored, "tokenOfOwnerByIndex/invalid-index-or-token");
  }

  // [ESCROW LOGIC]
  function testIonicLockAndVotingPower() public {
    uint256 tokenId;

    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    // change to some other chain ID
    vm.chainId(1);

    vm.expectRevert("wrong chain id");
    tokenId = ve.create_lock(20e18, 52 weeks);

    // revert back to the master chain ID
    vm.chainId(ve.ARBITRUM_ONE());
    tokenId = ve.create_lock(20e18, 52 weeks);

    assertApproxEqAbs(ve.balanceOfNFT(tokenId), 20e18, 1e17, "wrong voting power");
  }

  function _helperCreateLock() internal returns(uint256 tokenId) {
    ionicToken.mint(address(this), 100e18);

    ionicToken.approve(address(ve), 1e36);

    vm.chainId(ve.ARBITRUM_ONE());

    tokenId = ve.create_lock(20e18, 2 weeks);
  }

  function testIonicLockTimeIncrease() public {
    uint256 tokenId = _helperCreateLock();

    (int128 previousAmount, uint256 previousEnd) = ve.locked(tokenId);

    ve.increase_unlock_time(tokenId, 4 weeks);

    (int128 newAmount, uint256 newEnd) = ve.locked(tokenId);

    assertGt(newEnd, previousEnd, "newEnd less or equal");
    assertEq(int(newAmount), int(previousAmount), "amounts not equal");
  }

  function testIonicLockAmountIncrease() public {
    uint256 tokenId = _helperCreateLock();

    (int128 previousAmount, uint256 previousEnd) = ve.locked(tokenId);

    ve.increase_amount(tokenId, 20e18);

    (int128 newAmount, uint256 newEnd) = ve.locked(tokenId);

    assertEq(newEnd, previousEnd, "ends not equal");
    assertGt(int(newAmount), int(previousAmount), "newAmount less or equal");
  }

  function testCreateMarketGauges() public {

  }
}
