import { uniqueNamesGenerator, Config, adjectives, colors, animals } from 'unique-names-generator';

const customConfig: Config = {
  dictionaries: [adjectives, colors, animals],
  separator: '-',
  length: 3,
  style: 'lowerCase',
};

export const generateUniqueNameFromTimestamp = uniqueNamesGenerator({
  seed: Date.now(),
  ...customConfig,
})
