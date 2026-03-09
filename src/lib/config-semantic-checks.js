import { isKnownToolName } from './tool-registry.js';

export function validateSemanticConfig(config, policy) {
  const errors = [];
  const agentIds = new Set((config?.agents?.list || []).map((agent) => agent?.id).filter(Boolean));
  const bindings = config?.bindings || [];
  const allow = config?.tools?.subagents?.tools?.allow || [];
  const primaryAgent = (config?.agents?.list || []).find((agent) => agent?.id === policy?.primaryAgentId);
  const effectiveWorkspaceOnly = primaryAgent?.tools?.fs?.workspaceOnly ?? config?.tools?.fs?.workspaceOnly;
  const deniedTools = primaryAgent?.tools?.deny || [];

  if (policy?.primaryAgentId && !agentIds.has(policy.primaryAgentId)) {
    errors.push(`Primary agent must exist: ${policy.primaryAgentId}`);
  }

  const primaryBinding = bindings.find((binding) => binding?.match?.channel === policy?.primaryChannel);
  if (!primaryBinding) {
    errors.push(`Missing primary binding for channel: ${policy?.primaryChannel}`);
  } else if (primaryBinding.agentId !== policy.primaryAgentId) {
    errors.push(`Primary binding must resolve to ${policy.primaryAgentId}`);
  }

  for (const name of allow) {
    if (!isKnownToolName(name)) {
      errors.push(`Unknown tool name: ${name}`);
    }
  }

  if (policy?.requirePrimaryAgentWorkspaceOnly && effectiveWorkspaceOnly !== true) {
    errors.push('Primary agent must enforce tools.fs.workspaceOnly=true');
  }

  for (const deniedTool of policy?.requiredPrimaryAgentDeniedTools || []) {
    if (!deniedTools.includes(deniedTool)) {
      errors.push(`Primary agent must deny tool: ${deniedTool}`);
    }
  }

  const timeoutValue = config?.agents?.defaults?.subagents?.runTimeoutSeconds;
  if (policy?.forbidRunTimeoutSecondsZero && (timeoutValue === 0 || timeoutValue === undefined)) {
    errors.push('runTimeoutSeconds must be set and must not be 0 for v1');
  }

  return { ok: errors.length === 0, errors };
}
