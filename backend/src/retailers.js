const destinations = {
  US: [['Amazon', 'amazon.com'], ['Walmart', 'walmart.com'], ['eBay', 'ebay.com'], ['Target', 'target.com'], ['Best Buy', 'bestbuy.com']],
  FR: [['Cdiscount', 'cdiscount.com'], ['Fnac', 'fnac.com'], ['Darty', 'darty.com'], ['Decathlon', 'decathlon.fr'], ['Carrefour', 'carrefour.fr'], ['Auchan', 'auchan.fr']],
};

export const defaultRetailers = Object.entries(destinations).flatMap(([country, shops]) =>
  shops.map(([name, host]) => ({ name, country, url: `https://www.${host}/`, logoUrl: `https://www.${host}/favicon.ico`, enabled: true }))
);

export function validRetailerUrl(value) {
  if (typeof value !== 'string' || value.length > 2000) return false;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && url.hostname.includes('.');
  } catch {
    return false;
  }
}
