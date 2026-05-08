export const appName = 'Livy TLSNotary Docs';
export const docsRoute = '/docs';
export const docsImageRoute = '/og/docs';
export const docsContentRoute = '/llms.mdx/docs';

export const projectRepos = {
  tlsn: {
    name: 'tlsn',
    url: 'https://github.com/livylabs/tlsn',
    implementationBranch: 'tee_dev',
    benchmarkBranch: 'benchmark',
  },
  livyTlsn: {
    name: 'livy-tlsn',
    url: 'https://github.com/livylabs/livy-tlsn',
  },
} as const;

// Set this if/when the docs repo is pushed to GitHub.
export const gitConfig = {
  user: '',
  repo: '',
  branch: 'main',
} as const;

export function getDocsGithubUrl(path = ''): string | undefined {
  if (!gitConfig.user || !gitConfig.repo) return undefined;

  const normalizedPath = path.replace(/^\/+/, '');
  const base = `https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}`;

  return normalizedPath ? `${base}/${normalizedPath}` : base;
}
