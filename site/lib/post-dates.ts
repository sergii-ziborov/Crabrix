type DatedPost = { date: string; publishedDate?: string; modifiedDate?: string };

// Editorial/backfill dates can precede actual publication. Search metadata
// consistently uses the recorded publication/update dates, never build time.
export const postPublicationDate = (post: DatedPost) => post.publishedDate ?? post.date;
export const postModificationDate = (post: DatedPost) => post.modifiedDate ?? postPublicationDate(post);
