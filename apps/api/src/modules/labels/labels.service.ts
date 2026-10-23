import type { ConversationLabels, CreateLabelInput, Label, UpdateLabelInput } from "@repo/contracts";
import type { Database } from "@repo/db";

import { toConversationLabels, toLabel } from "../../lib/dto";
import { ConflictError, NotFoundError } from "../../lib/errors";
import { labelsRepo } from "./labels.repo";

export function labelsService(db: Database) {
    const repo = labelsRepo(db);

    async function findOrThrow(userId: string, id: string) {
        const label = await repo.find(userId, id);
        if (!label) throw new NotFoundError("That label doesn't exist anymore.");
        return label;
    }

    return {
        async create(userId: string, input: CreateLabelInput): Promise<Label> {
            // The app generates the id, so an existing one means a retry whose first response got lost.
            const existing = await repo.find(userId, input.id);
            if (existing) return toLabel(existing);
            if (await repo.nameTaken(userId, input.name)) {
                throw new ConflictError(`There's already a label called ${input.name}.`);
            }
            return toLabel(await repo.create({ ...input, userId }));
        },
        async update(userId: string, id: string, input: UpdateLabelInput): Promise<Label> {
            const label = await findOrThrow(userId, id);
            if (input.name !== undefined && (await repo.nameTaken(userId, input.name, id))) {
                throw new ConflictError(`There's already a label called ${input.name}.`);
            }
            if (input.name === undefined && input.description === undefined) return toLabel(label);
            const row = await repo.update(userId, id, {
                name: input.name,
                // An empty description is no description: the label goes back to never being applied by AI.
                description: input.description === undefined ? undefined : input.description || null,
            });
            if (!row) throw new NotFoundError("That label doesn't exist anymore.");
            return toLabel(row);
        },
        async remove(userId: string, id: string): Promise<void> {
            await findOrThrow(userId, id);
            await repo.remove(userId, id);
        },
        /** Replaces the conversation's labels. The conversation can be any id, the labels must all be live. */
        async setConversationLabels(
            userId: string,
            conversationId: string,
            labelIds: string[],
        ): Promise<ConversationLabels> {
            const ids = [...new Set(labelIds)];
            if (!(await repo.allLive(userId, ids))) throw new NotFoundError("That label doesn't exist anymore.");
            return toConversationLabels(await repo.setConversationLabels(userId, conversationId, ids));
        },
    };
}
