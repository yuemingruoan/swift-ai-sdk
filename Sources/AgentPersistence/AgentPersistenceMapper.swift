import AgentCore
import Foundation

public enum AgentPersistenceMapper {
    public static func sessionRecord(from session: AgentSession) -> AgentSessionRecord {
        AgentSessionRecord(id: session.id)
    }

    public static func session(from record: AgentSessionRecord) -> AgentSession {
        AgentSession(id: record.id)
    }

    public static func turnRecord(from turn: AgentTurn) -> AgentTurnRecord {
        AgentTurnRecord(
            sessionID: turn.sessionID,
            input: turn.input,
            output: turn.output,
            sequenceNumber: turn.sequenceNumber
        )
    }

    public static func turn(from record: AgentTurnRecord) -> AgentTurn {
        AgentTurn(
            sessionID: record.sessionID,
            input: record.input,
            output: record.output,
            sequenceNumber: record.sequenceNumber
        )
    }
}
