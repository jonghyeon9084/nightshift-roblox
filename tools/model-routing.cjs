'use strict';
// Deterministic dispatch policy; never calls an API or changes a running turn.
function selectModel(policy, role, request) {
  const task = typeof request === 'object' && request ? request : { tier: request };
  const workload = task.workload && policy.workloads?.[task.workload];
  if (task.workload && !workload) throw Error('Unknown workload');
  let tier = task.tier || workload?.tier;
  if (task.risks?.some(r => ['persistence','security','currency','concurrency'].includes(r))) tier = 'critical';
  if (task.unresolvedFailure === true) tier = 'hard-debug';
  const selection = tier ? policy.tiers[tier] : policy.roles[role];
  if (!selection) throw Error('Unknown role or difficulty');
  return { ...selection, tier: tier || 'role-default', reason: selection.reason || workload?.reason || `Role: ${role}` };
}
function validateSelection(selection, catalog) {
  const model = catalog.models?.find(m => m.slug === selection.model);
  if (!model) throw Error('Model not present in current Codex catalog');
  if (!model.supported_reasoning_levels?.some(r => r.effort === selection.effort)) throw Error('Reasoning level not supported by current model catalog');
  return selection;
}
function assertInactive(name, chats) {
  if (chats.some(c => (c.isActive || !['idle','stopped'].includes(c.state)) && c.participants?.some(p => p.name === name))) throw Error('Worker is active; model change deferred until its next task');
}
module.exports = { selectModel, validateSelection, assertInactive };
