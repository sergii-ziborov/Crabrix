export const BLOG_PAGE_SIZE = 12;

export function blogPagePath(page: number): string {
  return page === 1 ? "/blog/" : `/blog/page/${page}/`;
}

export function parseBlogPage(value: string): number | undefined {
  if (!/^[1-9]\d{0,15}$/.test(value)) return undefined;
  const page = Number(value);
  return Number.isSafeInteger(page) ? page : undefined;
}

export function blogPage<T>(posts: readonly T[], page: number) {
  const pageCount = Math.max(1, Math.ceil(posts.length / BLOG_PAGE_SIZE));
  if (!Number.isSafeInteger(page) || page < 1 || page > pageCount) return undefined;
  const offset = (page - 1) * BLOG_PAGE_SIZE;
  return {
    page,
    pageCount,
    posts: posts.slice(offset, offset + BLOG_PAGE_SIZE),
    total: posts.length,
    start: posts.length ? offset + 1 : 0,
    end: Math.min(offset + BLOG_PAGE_SIZE, posts.length),
  };
}
