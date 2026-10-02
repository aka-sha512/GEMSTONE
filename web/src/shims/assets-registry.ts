// react-native-svg's <Image> imports react native's asset registry
// gem-stone bundles no images, so on web the lookup always misses
export const getAssetByID = (id: number): undefined => void id;
export const registerAsset = (asset: unknown): number => (void asset, 0);
