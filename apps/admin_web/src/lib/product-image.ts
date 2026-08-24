/** Product photos, small enough to live in an inventory response.
 *
 *  image_data is a text column holding a data URI, and every inventory fetch
 *  carries it — POS included, on a counter machine, on a shop's connection.
 *  A 4MB phone photo pasted in raw would be paid for on every load by every
 *  client, so anything arriving from a file input is resized and re-encoded
 *  before it is ever saved.
 *
 *  The measuring and the decisions live here as pure functions so they can be
 *  tested; the canvas work below is the thin part that cannot be.
 */

/** Longest edge, in pixels, of a stored product photo. */
export const MAX_EDGE = 400;

/** Refuse to store anything bigger than this, after compression. */
export const MAX_BYTES = 60_000;

/** What a file input is allowed to offer. */
export const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];

export type Size = { width: number; height: number };

/**
 * Scales a photo down to fit inside a square of `maxEdge`, keeping its shape.
 * A picture already smaller than the box is left alone — upscaling a small
 * image only invents pixels and makes the data URI bigger.
 */
export function fitWithin(size: Size, maxEdge: number = MAX_EDGE): Size {
  const { width, height } = size;
  if (width <= 0 || height <= 0) {
    return { width: 0, height: 0 };
  }
  const longest = Math.max(width, height);
  if (longest <= maxEdge) {
    return { width: Math.round(width), height: Math.round(height) };
  }
  const scale = maxEdge / longest;
  return {
    // At least 1px: a very wide, very short image must not round to zero.
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

/**
 * How many bytes a data URI actually costs. The base64 payload is 4 characters
 * per 3 bytes, and trailing "=" padding stands for bytes that are not there.
 */
export function dataUriBytes(dataUri: string): number {
  const comma = dataUri.indexOf(",");
  if (comma === -1) {
    return 0;
  }
  const payload = dataUri.slice(comma + 1);
  const padding = payload.endsWith("==") ? 2 : payload.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor((payload.length * 3) / 4) - padding);
}

export function isAcceptedType(type: string): boolean {
  return ACCEPTED_TYPES.includes(type.toLowerCase());
}

/** A human-sized description, for the "too big" message. */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * The quality ladder used when the first encode comes out too heavy. Each
 * step is tried in turn and the first one under the cap wins, so a simple
 * packet shot keeps its quality and only a busy photograph gets squeezed.
 */
export const QUALITY_STEPS = [0.82, 0.7, 0.6, 0.5, 0.4];

/**
 * Reads an image file and returns a small JPEG data URI, or throws with a
 * message worth showing to a shopkeeper.
 *
 * JPEG rather than the original format: a PNG photograph is several times
 * larger for no visible gain, and transparency is meaningless on a product
 * shot sitting on a card.
 */
export async function fileToProductImage(
  file: File,
  maxEdge: number = MAX_EDGE,
): Promise<string> {
  if (!isAcceptedType(file.type)) {
    throw new Error("That file is not a JPEG, PNG or WebP image.");
  }

  const bitmap = await loadBitmap(file);
  const size = fitWithin({ width: bitmap.width, height: bitmap.height }, maxEdge);

  const canvas = document.createElement("canvas");
  canvas.width = size.width;
  canvas.height = size.height;
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("This browser could not process the image.");
  }
  // A white ground, so a transparent PNG does not become a black square once
  // it is flattened into a JPEG.
  context.fillStyle = "#FFFFFF";
  context.fillRect(0, 0, size.width, size.height);
  context.drawImage(bitmap, 0, 0, size.width, size.height);

  for (const quality of QUALITY_STEPS) {
    const uri = canvas.toDataURL("image/jpeg", quality);
    if (dataUriBytes(uri) <= MAX_BYTES) {
      return uri;
    }
  }

  throw new Error(
    "That picture is too detailed to store. Try a plainer photo of the packet.",
  );
}

async function loadBitmap(file: File): Promise<ImageBitmap | HTMLImageElement> {
  if (typeof createImageBitmap === "function") {
    return createImageBitmap(file);
  }
  // Safari fallback.
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("That image could not be opened."));
    };
    img.src = url;
  });
}
