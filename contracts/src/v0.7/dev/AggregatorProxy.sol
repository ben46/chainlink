// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../ConfirmedOwner.sol";
import "../interfaces/AggregatorProxyInterface.sol";

/**
 * @title 用于更新当前答案读取位置的可信代理
 * @notice 该合约为CurrentAnswerInterface提供了一个一致的地址，
 * 但将读取位置委托给所有者，信任其进行更新。
 */
contract AggregatorProxy is AggregatorProxyInterface, ConfirmedOwner {
  struct Phase {
    uint16 id;
    AggregatorProxyInterface aggregator;
  }
  AggregatorProxyInterface private s_proposedAggregator;
  mapping(uint16 => AggregatorProxyInterface) private s_phaseAggregators;
  Phase private s_currentPhase;

  uint256 private constant PHASE_OFFSET = 64;
  uint256 private constant PHASE_SIZE = 16;
  uint256 private constant MAX_ID = 2 ** (PHASE_OFFSET + PHASE_SIZE) - 1;

  event AggregatorProposed(address indexed current, address indexed proposed);
  event AggregatorConfirmed(address indexed previous, address indexed latest);

  constructor(address aggregatorAddress) ConfirmedOwner(msg.sender) {
    setAggregator(aggregatorAddress);
  }

  /**
   * @notice 从委托的聚合器中读取当前答案。
   *
   * @dev #[已弃用] 使用latestRoundData代替。如果还没有达到答案，这不会出错，它只会返回0。
   * 要么等待指向已经有答案的聚合器，要么使用推荐的latestRoundData，它包含更好的验证信息。
   */
  function latestAnswer() public view virtual override returns (int256 answer) {
    return s_currentPhase.aggregator.latestAnswer();
  }

  /**
   * @notice 从委托的聚合器中读取上次更新的时间戳。
   *
   * @dev #[已弃用] 使用latestRoundData代替。如果还没有达到答案，这不会出错，它只会返回0。
   * 要么等待指向已经有答案的聚合器，要么使用推荐的latestRoundData，它包含更好的验证信息。
   */
  function latestTimestamp() public view virtual override returns (uint256 updatedAt) {
    return s_currentPhase.aggregator.latestTimestamp();
  }

  /**
   * @notice 获取过去轮次的答案
   * @param roundId 要检索答案的轮次号
   *
   * @dev #[已弃用] 使用getRoundData代替。如果还没有达到答案，这不会出错，它只会返回0。
   * 要么等待指向已经有答案的聚合器，要么使用推荐的getRoundData，它包含更好的验证信息。
   */
  function getAnswer(uint256 roundId) public view virtual override returns (int256 answer) {
    if (roundId > MAX_ID) return 0;

    (uint16 phaseId, uint64 aggregatorRoundId) = parseIds(roundId);
    AggregatorProxyInterface aggregator = s_phaseAggregators[phaseId];
    if (address(aggregator) == address(0)) return 0;

    return aggregator.getAnswer(aggregatorRoundId);
  }

  /**
   * @notice 获取上次更新答案时的区块时间戳
   * @param roundId 要检索更新时间戳的答案编号
   *
   * @dev #[已弃用] 使用getRoundData代替。如果还没有达到答案，这不会出错，它只会返回0。
   * 要么等待指向已经有答案的聚合器，要么使用推荐的getRoundData，它包含更好的验证信息。
   */
  function getTimestamp(uint256 roundId) public view virtual override returns (uint256 updatedAt) {
    if (roundId > MAX_ID) return 0;

    (uint16 phaseId, uint64 aggregatorRoundId) = parseIds(roundId);
    AggregatorProxyInterface aggregator = s_phaseAggregators[phaseId];
    if (address(aggregator) == address(0)) return 0;

    return aggregator.getTimestamp(aggregatorRoundId);
  }

  /**
   * @notice 获取最新完成的轮次，其中更新了答案。
   * 此ID包括代理的阶段，以确保即使切换到新部署的聚合器，轮次ID也会增加。
   *
   * @dev #[已弃用] 使用latestRoundData代替。如果还没有达到答案，这不会出错，它只会返回0。
   * 要么等待指向已经有答案的聚合器，要么使用推荐的latestRoundData，它包含更好的验证信息。
   */
  function latestRound() public view virtual override returns (uint256 roundId) {
    Phase memory phase = s_currentPhase; // 缓存存储读取
    return addPhase(phase.id, uint64(phase.aggregator.latestRound()));
  }

  /**
   * @notice 获取有关轮次的数据。鼓励消费者通过检查updatedAt和answeredInRound返回值来确保接收到新鲜数据。
   * 请注意，不同的AggregatorV3Interface底层实现对某些返回值的语义有微小差异。
   * 消费者应确定他们期望从中接收数据的实现，并验证他们可以正确处理所有这些实现的返回数据。
   * @param roundId 通过代理呈现的请求的轮次ID，由聚合器的轮次ID组成，其中相位ID编码在最高的两个字节中
   * @return id 是从聚合器中检索数据的轮次ID，结合了相位，以确保随着时间的推移，轮次ID变大。
   * @return answer 是给定轮次的答案
   * @return startedAt 是轮次启动时的时间戳。
   * （仅某些AggregatorV3Interface实现返回有意义的值）
   * @return updatedAt 是轮次上次更新时的时间戳（即答案上次计算时的时间戳）
   * @return answeredInRound 是计算答案的轮次的轮次ID。
   * （仅某些AggregatorV3Interface实现返回有意义的值）
   * @dev 注意，答案和updatedAt在查询之间可能会发生变化。
   */
  function getRoundData(
    uint80 roundId
  )
    public
    view
    virtual
    override
    returns (uint80 id, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    (uint16 phaseId, uint64 aggregatorRoundId) = parseIds(roundId);

    (id, answer, startedAt, updatedAt, answeredInRound) = s_phaseAggregators[phaseId].getRoundData(aggregatorRoundId);

    return addPhaseIds(id, answer, startedAt, updatedAt, answeredInRound, phaseId);
  }

  /**
   * @notice 获取有关最新轮次的数据。鼓励消费者通过检查updatedAt和answeredInRound返回值来确保获得新鲜数据。
   * 请注意，AggregatorV3Interface的不同底层实现对某些返回值的语义略有不同。
   * 消费者应确定他们期望从中接收数据的实现，并验证他们可以正确处理所有这些实现的返回数据。
   * @return id 是从聚合器中检索数据的轮次ID，结合了相位，以确保随着时间的推移，轮次ID变大。
   * @return answer 是给定轮次的答案
   * @return startedAt 是轮次启动时的时间戳。
   * （仅某些AggregatorV3Interface实现返回有意义的值）
   * @return updatedAt 是轮次上次更新时的时间戳（即答案上次计算时的时间戳）
   * @return answeredInRound 是计算答案的轮次的轮次ID。
   * （仅某些AggregatorV3Interface实现返回有意义的值）
   * @dev 注意，答案和updatedAt在查询之间可能会发生变化。
   */
  function latestRoundData()
    public
    view
    virtual
    override
    returns (uint80 id, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    Phase memory current = s_currentPhase; // 缓存存储读取

    (id, answer, startedAt, updatedAt, answeredInRound) = current.aggregator.latestRoundData();

    return addPhaseIds(id, answer, startedAt, updatedAt, answeredInRound, current.id);
  }

  /**
   * @notice 如果已提出聚合器合约，则使用。
   * @param roundId 要检索轮次数据的轮次ID
   * @return id 是检索数据的轮次ID
   * @return answer 是给定轮次的答案
   * @return startedAt 是轮次启动时的时间戳。
   * （仅某些AggregatorV3Interface实现返回有意义的值）
   * @return updatedAt 是轮次上次更新时的时间戳（即答案上次计算时的时间戳）
   * @return answeredInRound 是计算答案的轮次的轮次ID。
   */
  function proposedGetRoundData(
    uint80 roundId
  )
    external
    view
    virtual
    override
    hasProposal
    returns (uint80 id, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return s_proposedAggregator.getRoundData(roundId);
  }

  /**
   * @notice 如果已提出聚合器合约，则使用。
   * @return id 是检索数据的轮次ID
   * @return answer 是给定轮次的答案
   * @return startedAt 是轮次启动时的时间戳。
   * （仅某些AggregatorV3Interface实现返回有意义的值）
   * @return updatedAt 是轮次上次更新时的时间戳（即答案上次计算时的时间戳）
   * @return answeredInRound 是计算答案的轮次的轮次ID。
   */
  function proposedLatestRoundData()
    external
    view
    virtual
    override
    hasProposal
    returns (uint80 id, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return s_proposedAggregator.latestRoundData();
  }

  /**
   * @notice 返回当前阶段的聚合器地址。
   */
  function aggregator() external view override returns (address) {
    return address(s_currentPhase.aggregator);
  }

  /**
   * @notice 返回当前阶段的ID。
   */
  function phaseId() external view override returns (uint16) {
    return s_currentPhase.id;
  }

  /**
   * @notice 表示聚合器响应所代表的小数位数。
   */
  function decimals() external view override returns (uint8) {
    return s_currentPhase.aggregator.decimals();
  }

  /**
   * @notice 代表代理指向的聚合器类型的版本号。
   */
  function version() external view override returns (uint256) {
    return s_currentPhase.aggregator.version();
  }

  /**
   * @notice 返回代理指向的聚合器的描述。
   */
  function description() external view override returns (string memory) {
    return s_currentPhase.aggregator.description();
  }

  /**
   * @notice 返回当前建议的聚合器
   */
  function proposedAggregator() external view override returns (address) {
    return address(s_proposedAggregator);
  }

  /**
   * @notice 使用phaseId返回一个阶段聚合器
   *
   * @param phaseId uint16
   */
  function phaseAggregators(uint16 phaseId) external view override returns (address) {
    return address(s_phaseAggregators[phaseId]);
  }

  /**
   * @notice 允许所有者为聚合器提出新地址
   * @param aggregatorAddress 聚合器合约的新地址
   */
  function proposeAggregator(address aggregatorAddress) external onlyOwner {
    s_proposedAggregator = AggregatorProxyInterface(aggregatorAddress);
    emit AggregatorProposed(address(s_currentPhase.aggregator), aggregatorAddress);
  }

  /**
   * @notice 允许所有者确认和更改建议的聚合器的地址
   * @dev 如果给定地址与先前提议的不匹配，则回滚
   * @param aggregatorAddress 聚合器合约的新地址
   */
  function confirmAggregator(address aggregatorAddress) external onlyOwner {
    require(aggregatorAddress == address(s_proposedAggregator), "Invalid proposed aggregator");
    address previousAggregator = address(s_currentPhase.aggregator);
    delete s_proposedAggregator;
    setAggregator(aggregatorAddress);
    emit AggregatorConfirmed(previousAggregator, aggregatorAddress);
  }

  /*
   * Internal
   */

  /**
   * @notice 设置聚合器
   * @param aggregatorAddress 聚合器合约的地址
   */
  function setAggregator(address aggregatorAddress) internal {
    uint16 id = s_currentPhase.id + 1;
    s_currentPhase = Phase(id, AggregatorProxyInterface(aggregatorAddress));
    s_phaseAggregators[id] = AggregatorProxyInterface(aggregatorAddress);
  }

  /**
   * @notice 添加阶段
   * @param phase 阶段
   * @param originalId 原始ID
   * @return uint80
   */
  function addPhase(uint16 phase, uint64 originalId) internal pure returns (uint80) {
    return uint80((uint256(phase) << PHASE_OFFSET) | originalId);
  }

  /**
   * @notice 解析ID
   * @param roundId 要解析的轮次ID
   * @return uint16 阶段ID
   * @return uint64 聚合器轮次ID
   */
  function parseIds(uint256 roundId) internal pure returns (uint16, uint64) {
    uint16 phaseId = uint16(roundId >> PHASE_OFFSET);
    uint64 aggregatorRoundId = uint64(roundId);

    return (phaseId, aggregatorRoundId);
  }

  /**
   * @notice 添加阶段ID
   * @param roundId 轮次ID
   * @param answer 答案
   * @param startedAt 轮次开始时间
   * @param updatedAt 轮次最后更新时间
   * @param answeredInRound 在哪个轮次中计算答案的轮次ID
   * @param phaseId 阶段ID
   * @return uint80
   * @return int256
   * @return uint256
   * @return uint256
   * @return uint80
   */
  function addPhaseIds(
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound,
    uint16 phaseId
  ) internal pure returns (uint80, int256, uint256, uint256, uint80) {
    return (
      addPhase(phaseId, uint64(roundId)),
      answer,
      startedAt,
      updatedAt,
      addPhase(phaseId, uint64(answeredInRound))
    );
  }

  /*
   * Modifiers
   */

  modifier hasProposal() {
    require(address(s_proposedAggregator) != address(0), "No proposed aggregator present");
    _;
  }
}
