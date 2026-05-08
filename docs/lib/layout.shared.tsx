import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';
import { appName, getDocsGithubUrl } from './shared';

export function baseOptions(): BaseLayoutProps {
  const githubUrl = getDocsGithubUrl();

  return {
    nav: {
      // JSX supported
      title: appName,
    },
    ...(githubUrl ? { githubUrl } : {}),
  };
}
