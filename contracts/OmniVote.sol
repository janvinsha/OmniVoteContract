// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract OmniVote is Ownable {
    using ECDSA for bytes32;

    // Structure to hold DAO information
    struct DAOInfo {
        address daoAddress;
        string name;
        string description;
        string ipfsMetadataHash; // IPFS hash for storing metadata like proposal descriptions, images, etc.
    }

    // Proposal structure
    struct Proposal {
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 quorum;
        uint256 totalVotes;
        mapping(address => bool) voters; // To track who has voted
        mapping(uint256 => uint256) options; // Voting options and their vote counts
    }

    // DAO and Proposal Storage
    mapping(bytes32 => DAOInfo) public daos;
    mapping(bytes32 => Proposal) public proposals;

    address public admin; // Admin of the Omnivote contract

    event DaoAdded(bytes32 indexed daoId, address daoAddress, string name, string description, string ipfsMetadataHash);
    event ProposalCreated(
        bytes32 indexed daoId,
        bytes32 indexed proposalId,
        string description,
        uint256 startTime,
        uint256 endTime,
        uint256 quorum
    );
    event VoteSubmitted(address indexed voter, bytes32 indexed proposalId, uint256 option, uint256 weight);
    event ProposalFinalized(bytes32 indexed proposalId, uint256[] results);
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier onlyDAOOwner(address _daoAddress) {
        // Implement a way to verify DAO ownership, this is a placeholder
        require(msg.sender == _daoAddress, "Not DAO owner");
        _;
    }

    constructor() Ownable() {}

    /**
     * @notice Adds a new DAO to the OmniVote contract.
     * @param _daoId Unique identifier for the DAO.
     * @param _daoAddress The address of the DAO contract.
     * @param _name The name of the DAO.
     * @param _description A brief description of the DAO.
     * @param _ipfsMetadataHash IPFS hash containing DAO metadata.
     */
    function addDao(
        bytes32 _daoId,
        address _daoAddress,
        string memory _name,
        string memory _description,
        string memory _ipfsMetadataHash
    ) external onlyOwner {
        require(_daoAddress != address(0), "Invalid DAO address");
        require(daos[_daoId].daoAddress == address(0), "DAO already exists");

        daos[_daoId] = DAOInfo(_daoAddress, _name, _description, _ipfsMetadataHash);
        emit DaoAdded(_daoId, _daoAddress, _name, _description, _ipfsMetadataHash);
    }

    /**
     * @notice Creates a new proposal in the specified DAO.
     * @param _daoId The identifier of the DAO.
     * @param _proposalId The identifier of the proposal.
     * @param _description Description of the proposal.
     * @param _startTime Start time of the proposal voting period.
     * @param _endTime End time of the proposal voting period.
     * @param _quorum Minimum number of votes required for the proposal to be valid.
     */
    function createProposal(
        bytes32 _daoId,
        bytes32 _proposalId,
        string calldata _description,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _quorum
    ) external onlyOwner {
        require(daos[_daoId].daoAddress != address(0), "DAO does not exist");
        require(_startTime < _endTime, "Invalid time range");

        Proposal storage proposal = proposals[_proposalId];
        proposal.description = _description;
        proposal.startTime = _startTime;
        proposal.endTime = _endTime;
        proposal.quorum = _quorum;

        emit ProposalCreated(_daoId, _proposalId, _description, _startTime, _endTime, _quorum);
    }

    /**
     * @notice Allows users to submit an off-chain vote.
     * @param _proposalId The ID of the proposal being voted on.
     * @param _option The voting option chosen by the user.
     * @param _weight The weight of the user's vote (e.g., number of tokens).
     * @param _signature The off-chain signature of the voter's address and vote details.
     */
    function submitVote(bytes32 _proposalId, uint256 _option, uint256 _weight, bytes memory _signature) external {
        Proposal storage proposal = proposals[_proposalId];
        require(
            block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime,
            "Voting period not active"
        );
        require(!proposal.voters[msg.sender], "Already voted");

        // Verify off-chain signature
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, _proposalId, _option, _weight));
        address signer = messageHash.toEthSignedMessageHash().recover(_signature);
        require(signer == msg.sender, "Invalid signature");

        proposal.voters[msg.sender] = true;
        proposal.options[_option] += _weight;
        proposal.totalVotes += _weight;

        emit VoteSubmitted(msg.sender, _proposalId, _option, _weight);
    }

    /**
     * @notice Finalizes a proposal and calculates the results.
     * @param _proposalId The ID of the proposal to finalize.
     */
    function finalizeProposal(bytes32 _proposalId) external onlyOwner {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not yet ended");

        uint256[] memory results = new uint256[](proposal.totalVotes);
        uint256 resultCount = 0;

        for (uint256 i = 0; i < proposal.totalVotes; i++) {
            results[i] = proposal.options[i];
            resultCount++;
        }

        emit ProposalFinalized(_proposalId, results);
    }

    /**
     * @notice Returns the details of a proposal.
     * @param _proposalId The ID of the proposal.
     * @return description The description of the proposal.
     * @return startTime Start time of the proposal voting period.
     * @return endTime End time of the proposal voting period.
     * @return quorum Minimum number of votes required for the proposal to be valid.
     * @return totalVotes Total votes cast for the proposal.
     */
    function getProposalDetails(
        bytes32 _proposalId
    )
        external
        view
        returns (string memory description, uint256 startTime, uint256 endTime, uint256 quorum, uint256 totalVotes)
    {
        Proposal storage proposal = proposals[_proposalId];
        return (proposal.description, proposal.startTime, proposal.endTime, proposal.quorum, proposal.totalVotes);
    }
}
