import types from '../mutation-types';
import BulkActionsAPI from '../../api/bulkActions';

export const state = {
  selectedConversationIds: [],
  // Explicit multi-select mode: every card shows its checkbox (not only on avatar hover).
  selectionMode: false,
  uiFlags: {
    isUpdating: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getSelectedConversationIds(_state) {
    return _state.selectedConversationIds;
  },
  getSelectionMode(_state) {
    return _state.selectionMode;
  },
};

export const actions = {
  process: async function processAction({ commit }, payload) {
    commit(types.SET_BULK_ACTIONS_FLAG, { isUpdating: true });
    try {
      await BulkActionsAPI.create(payload);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_BULK_ACTIONS_FLAG, { isUpdating: false });
    }
  },
  setSelectedConversationIds({ commit }, id) {
    commit(types.SET_SELECTED_CONVERSATION_IDS, id);
  },
  removeSelectedConversationIds({ commit }, id) {
    commit(types.REMOVE_SELECTED_CONVERSATION_IDS, id);
  },
  clearSelectedConversationIds({ commit }) {
    commit(types.CLEAR_SELECTED_CONVERSATION_IDS);
  },
  setSelectionMode({ commit }, enabled) {
    commit(types.SET_CONVERSATION_SELECTION_MODE, enabled);
    if (!enabled) commit(types.CLEAR_SELECTED_CONVERSATION_IDS);
  },
};

export const mutations = {
  [types.SET_BULK_ACTIONS_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_SELECTED_CONVERSATION_IDS](_state, ids) {
    // Check if ids is an array, if not, convert it to an array
    const idsArray = Array.isArray(ids) ? ids : [ids];

    // Concatenate the new IDs ensuring no duplicates
    _state.selectedConversationIds = [
      ...new Set([..._state.selectedConversationIds, ...idsArray]),
    ];
  },
  [types.REMOVE_SELECTED_CONVERSATION_IDS](_state, id) {
    _state.selectedConversationIds = _state.selectedConversationIds.filter(
      item => item !== id
    );
  },
  [types.CLEAR_SELECTED_CONVERSATION_IDS](_state) {
    _state.selectedConversationIds = [];
  },
  [types.SET_CONVERSATION_SELECTION_MODE](_state, enabled) {
    _state.selectionMode = Boolean(enabled);
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
