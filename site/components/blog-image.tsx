import type { PostImage } from "@/lib/posts";

export function BlogImage({ image, decorative = false, card = false, priority = false }: {
  image: PostImage; decorative?: boolean; card?: boolean; priority?: boolean;
}) {
  const stem = image.src.replace(/\.png$/, "");
  return <picture>
    <source type="image/webp"
      srcSet={`${stem}-640.webp 640w, ${stem}.webp ${image.width ?? 1536}w`}
      sizes={card ? "(max-width: 700px) 100vw, (max-width: 1000px) 50vw, 33vw" : "(max-width: 800px) 100vw, 780px"} />
    <img className={card ? "post-cover" : undefined} src={image.src}
      alt={decorative ? "" : image.alt} width={image.width} height={image.height}
      loading={priority ? "eager" : "lazy"} fetchPriority={priority ? "high" : "auto"} />
  </picture>;
}
