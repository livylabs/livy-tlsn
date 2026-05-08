import Link from 'next/link';
import { projectRepos } from '@/lib/shared';

export default function HomePage() {
  return (
    <div className="flex flex-1 items-center justify-center px-6 py-16">
      <div className="mx-auto flex max-w-3xl flex-col items-center gap-6 text-center">
        <p className="text-sm font-medium uppercase tracking-[0.24em] text-fd-muted-foreground">
          Livy Labs
        </p>
        <div className="space-y-4">
          <h1 className="text-4xl font-semibold tracking-tight sm:text-5xl">
            TLSNotary TEE Documentation
          </h1>
          <p className="text-base text-fd-muted-foreground sm:text-lg">
            Runbooks and technical notes for the TDX-backed TLSNotary deployment across{' '}
            <code>{projectRepos.tlsn.name}</code> and <code>{projectRepos.livyTlsn.name}</code>.
          </p>
        </div>
        <div className="flex flex-wrap items-center justify-center gap-3">
          <Link
            href="/docs"
            className="rounded-full bg-fd-primary px-5 py-2.5 text-sm font-medium text-fd-primary-foreground"
          >
            Open Docs
          </Link>
          <Link
            href={projectRepos.tlsn.url}
            target="_blank"
            rel="noreferrer"
            className="rounded-full border px-5 py-2.5 text-sm font-medium"
          >
            {projectRepos.tlsn.name}
          </Link>
          <Link
            href={projectRepos.livyTlsn.url}
            target="_blank"
            rel="noreferrer"
            className="rounded-full border px-5 py-2.5 text-sm font-medium"
          >
            {projectRepos.livyTlsn.name}
          </Link>
        </div>
      </div>
    </div>
  );
}
