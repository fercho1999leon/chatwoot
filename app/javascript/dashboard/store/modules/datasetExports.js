import * as types from '../mutation-types';
import DatasetExportsAPI from '../../api/datasetExports';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
  },
};

const getters = {
  getDatasetExports(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  async fetch({ commit }) {
    commit(types.default.SET_DATASET_EXPORTS_UI_FLAG, { fetchingList: true });
    try {
      const { data } = await DatasetExportsAPI.get();
      commit(types.default.SET_DATASET_EXPORTS, data.payload);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.default.SET_DATASET_EXPORTS_UI_FLAG, {
        fetchingList: false,
      });
    }
  },

  async delete({ commit }, id) {
    try {
      await DatasetExportsAPI.delete(id);
      commit(types.default.DELETE_DATASET_EXPORT, id);
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};

export const mutations = {
  [types.default.DELETE_DATASET_EXPORT](_state, id) {
    _state.records = _state.records.filter(record => record.id !== id);
  },
  [types.default.SET_DATASET_EXPORTS](_state, records) {
    _state.records = records;
  },
  [types.default.SET_DATASET_EXPORTS_UI_FLAG](_state, uiFlags) {
    _state.uiFlags = { ..._state.uiFlags, ...uiFlags };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
