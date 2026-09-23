import ApiClient from './ApiClient';

class DatasetExportsAPI extends ApiClient {
  constructor() {
    super('dataset_exports', { accountScoped: true });
  }
}

export default new DatasetExportsAPI();
